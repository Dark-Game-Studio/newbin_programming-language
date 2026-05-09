# bing_integration.nim
import httpclient, json, uri

type
  BingClient = object
    apiKey: string
    endpoint: string

proc newBingClient(apiKey: string): BingClient =
  result.apiKey = apiKey
  result.endpoint = "https://api.bing.microsoft.com/v7.0/search"

proc search(bing: BingClient, query: string): string =
  var client = newHttpClient()
  client.headers = newHttpHeaders({
    "Ocp-Apim-Subscription-Key": bing.apiKey
  })
  
  let url = bing.endpoint & "?q=" & encodeUrl(query)
  let response = client.getContent(url)
  client.close()
  
  # Parse JSON response
  let jsonNode = parseJson(response)
  # Extract search results
  return jsonNode.pretty()