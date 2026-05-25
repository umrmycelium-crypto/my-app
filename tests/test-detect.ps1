# test-detect.ps1
$uri = "http://localhost:8080/detect"
$body = @{
  type = "battery_pack"
  attributes = @{
    scuffing_score = 0.2
    wear_score = 0.7
    color = "black"
  }
  confidence = 0.92
} | ConvertTo-Json -Depth 5

Write-Host "Posting detection to $uri"
$response = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType "application/json"
Write-Host "Response:"
$response | ConvertTo-Json -Depth 5
