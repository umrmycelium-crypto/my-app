# Mycelium AI Start Script
# This starts the transcription worker and information flow.

Write-Host "Starting Mycelium Transcription Worker..." -ForegroundColor Cyan
cd C:\Users\marcu\mycelium-core\services\transcription_worker
# Check if venv exists, if not create it (simplified for this script)
if (-not (Test-Path "venv")) {
    Write-Host "Creating virtual environment..."
    python -m venv venv
}
.\venv\Scripts\activate
pip install -r requirements.txt
Start-Process python -ArgumentList "app.py" -NoNewWindow

Write-Host "AI Layer is ready at http://localhost:8090" -ForegroundColor Green
Write-Host "Update forge-chat to use this worker." -ForegroundColor Yellow
Write-Host "Access the UI at http://localhost:5000/ai-layer" -ForegroundColor Green
