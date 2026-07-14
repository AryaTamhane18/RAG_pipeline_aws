# import json
# import boto3
# import urllib.request
# import urllib.error

# def get_secret():
#     client = boto3.client("secretsmanager", region_name="us-east-1")
#     secret = client.get_secret_value(SecretId="rag/openai-api-key")
#     return json.loads(secret["SecretString"])

# def call_gemini(question, gemini_key):
#     url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key={gemini_key}"
    
#     payload = json.dumps({
#         "contents": [
#             {
#                 "parts": [
#                     {"text": question}
#                 ]
#             }
#         ]
#     }).encode("utf-8")

#     req = urllib.request.Request(
#         url,
#         data=payload,
#         headers={"Content-Type": "application/json"},
#         method="POST"
#     )

#     with urllib.request.urlopen(req) as resp:
#         result = json.loads(resp.read().decode("utf-8"))

#     return result["candidates"][0]["content"]["parts"][0]["text"]

# def lambda_handler(event, context):
#     try:
#         # 1. Read Gemini key from Secrets Manager at runtime
#         secrets = get_secret()
#         gemini_key = secrets["gemini_key"]

#         # 2. Get question from request body
#         body = json.loads(event.get("body") or '{}')
#         question = body.get("question", "What is Retrieval Augmented Generation?")

#         # 3. Call Gemini API
#         answer = call_gemini(question, gemini_key)

#         # 4. Return result
#         return {
#             "statusCode": 200,
#             "headers": {"Content-Type": "application/json"},
#             "body": json.dumps({
#                 "question": question,
#                 "answer": answer,
#                 "source": "gemini-2.0-flash",
#                 "phase": "Phase 2 - External API Integration Live"
#             })
#         }

#     except urllib.error.HTTPError as e:
#         error_body = e.read().decode("utf-8")
#         return {
#             "statusCode": e.code,
#             "body": json.dumps({
#                 "error": f"API call failed: {e.code}",
#                 "detail": error_body
#             })
#         }
#     except Exception as e:
#         return {
#             "statusCode": 500,
#             "body": json.dumps({"error": str(e)})
#         }
import json
import boto3
import urllib.request
import urllib.error
import uuid
import time

def get_secret():
    client = boto3.client("secretsmanager", region_name="us-east-1")
    secret = client.get_secret_value(SecretId="rag/openai-api-key")
    return json.loads(secret["SecretString"])

def call_gemini(question, gemini_key):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key={gemini_key}"

    payload = json.dumps({
        "contents": [
            {"parts": [{"text": question}]}
        ]
    }).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read().decode("utf-8"))

    return result["candidates"][0]["content"]["parts"][0]["text"]

def save_to_dynamodb(question, answer):
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    table = dynamodb.Table("rag-qa-records")
    table.put_item(Item={
        "record_id": str(uuid.uuid4()),
        "question":  question,
        "answer":    answer,
        "source":    "gemini-3.1-flash-lite",
        "timestamp": int(time.time()),
        "ttl":       int(time.time()) + 30 * 24 * 3600
    })

def lambda_handler(event, context):
    try:
        # 1. Read Gemini key from Secrets Manager
        secrets = get_secret()
        gemini_key = secrets["gemini_key"]

        # 2. Get question from request body
        body = json.loads(event.get("body") or '{}')
        question = body.get("question", "What is Retrieval Augmented Generation?")

        # 3. Call Gemini API
        answer = call_gemini(question, gemini_key)

        # 4. Save Q&A record to DynamoDB
        save_to_dynamodb(question, answer)

        # 5. Return result
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "question": question,
                "answer": answer,
                "source": "gemini-3.1-flash-lite",
                "phase": "Phase 2 - External API Integration Live",
                "stored": "DynamoDB"
            })
        }

    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        return {
            "statusCode": e.code,
            "body": json.dumps({
                "error": f"API call failed: {e.code}",
                "detail": error_body
            })
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }