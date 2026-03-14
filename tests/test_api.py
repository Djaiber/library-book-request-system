import requests
import sys
import time
import os

def test_api_endpoint():
    api_url = os.environ['API_URL']  # ← read from env, not hardcoded
    
    if not api_url:
        raise ValueError("API_URL environment variable is not set")
    
    print(f"Testing API endpoint: {api_url}")

    # Test 1: Health check (OPTIONS)
    options_response = requests.options(api_url)
    assert options_response.status_code == 200, f"OPTIONS failed: {options_response.status_code}"
    print("✅ OPTIONS request successful")

    # Test 2: Valid request
    payload = {
        "isbn": "9780451524935",
        "requesterEmail": "smoke-test@example.com",
        "query": "smoke test",
        "notes": "Production smoke test"
    }
    response = requests.post(api_url, json=payload)
    assert response.status_code == 202, f"Expected 202, got {response.status_code}: {response.text}"

    data = response.json()
    assert "requestId" in data, "Response missing requestId"
    assert "sqsMessageId" in data, "Response missing sqsMessageId"
    print(f"✅ Valid request successful - Request ID: {data['requestId']}")

    # Test 3: Invalid request (missing search params)
    invalid_payload = {"requesterEmail": "smoke-test@example.com"}
    response = requests.post(api_url, json=invalid_payload)
    assert response.status_code == 400, f"Expected 400, got {response.status_code}"
    print("✅ Invalid request correctly rejected")

    print("⏳ Waiting for consumer to process...")
    time.sleep(5)
    return True

if __name__ == "__main__":
    try:
        test_api_endpoint()
        print("\n🎉 All smoke tests passed!")
        sys.exit(0)
    except AssertionError as e:
        print(f"\n❌ Smoke test failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)