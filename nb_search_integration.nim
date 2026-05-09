# nb_search_integration.nim
import httpclient, asyncdispatch, json, uri, strutils
import std/asyncfutures

type
  WebSearchEngine* = enum
    wsBing
    wsGoogle
    wsCustom

  SearchResult* = object
    title*: string
    url*: string
    snippet*: string
    rank*: int

  SearchClient* = ref object
    engine*: WebSearchEngine
    apiKey*: string
    endpoint*: string
    cache*: TableRef[string, seq[SearchResult]]
    rateLimiter: RateLimiter

  RateLimiter = object
    lastRequest: float
    minDelay: float  # seconds between requests

proc initRateLimiter*(delay: float = 1.0): RateLimiter =
  RateLimiter(lastRequest: 0.0, minDelay: delay)

proc newSearchClient*(apiKey: string, engine: WebSearchEngine = wsBing): SearchClient =
  SearchClient(
    engine: engine,
    apiKey: apiKey,
    endpoint: case engine
      of wsBing: "https://api.bing.microsoft.com/v7.0/search"
      of wsGoogle: "https://www.googleapis.com/customsearch/v1"
      of wsCustom: "https://api.example.com/search",
    cache: newTable[string, seq[SearchResult]](),
    rateLimiter: initRateLimiter()
  )

proc searchBing(client: SearchClient, query: string, count: int = 10): Future[seq[SearchResult]] {.async.} =
  # Check cache first
  if query in client.cache:
    return client.cache[query]

  # Rate limiting
  let now = epochTime()
  let elapsed = now - client.rateLimiter.lastRequest
  if elapsed < client.rateLimiter.minDelay:
    await sleepAsync(int((client.rateLimiter.minDelay - elapsed) * 1000))
  
  client.rateLimiter.lastRequest = epochTime()

  var httpClient = newAsyncHttpClient()
  httpClient.headers = newHttpHeaders({
    "Ocp-Apim-Subscription-Key": client.apiKey,
    "Accept": "application/json"
  })

  let params = {
    "q": query,
    "count": $count,
    "mkt": "en-US",
    "safesearch": "Moderate",
    "responseFilter": "Webpages",
    "textFormat": "Raw"
  }

  let url = client.endpoint & "?" & encodeQuery(params)
  
  try:
    let response = await httpClient.get(url)
    let body = await response.body
    
    if response.status != "200":
      raise newException(HttpRequestError, 
        "Bing API returned status " & response.status & ": " & body)

    let jsonNode = parseJson(body)
    var results: seq[SearchResult]
    
    if jsonNode.hasKey("webPages") and jsonNode["webPages"].hasKey("value"):
      for i, item in jsonNode["webPages"]["value"]:
        results.add(SearchResult(
          title: item["name"].getStr(),
          url: item["url"].getStr(),
          snippet: item["snippet"].getStr(),
          rank: i + 1
        ))

    # Cache results
    client.cache[query] = results
    return results
  
  except HttpRequestError:
    echo "Network error during search: ", getCurrentExceptionMsg()
    return @[]
  finally:
    httpClient.close()

proc searchWeb*(client: SearchClient, query: string, count: int = 10): Future[seq[SearchResult]] {.async.} =
  case client.engine
  of wsBing:
    return await searchBing(client, query, count)
  of wsGoogle:
    raise newException(ValueError, "Google search not yet implemented")
  of wsCustom:
    raise newException(ValueError, "Custom search engine not configured")

# === VM Integration ===
type
  SearchContext* = ref object
    client*: SearchClient
    pendingSearches*: seq[Future[seq[SearchResult]]]
    searchResults*: TableRef[string, SearchResult]

proc searchInVM*(ctx: SearchContext, query: string, slot: int) =
  let future = searchWeb(ctx.client, query)
  
  # Add callback when search completes
  future.addCallback(proc() =
    if future.failed:
      echo "Search failed: ", future.error.msg
      return
    
    let results = future.read()
    if results.len > 0:
      ctx.searchResults[$slot] = results[0]
  )
  
  ctx.pendingSearches.add(future)