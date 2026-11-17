import requests

SUPABASE_URL = "https://acwpurtriixeweteipjl.supabase.co"
ANON_KEY = "sb_publishable_xSUf6MaL26tLNLo3cGHriA_bWfHhXhb"
TABLE_NAME = "students"

headers = {
    "apikey": ANON_KEY,
    "Authorization": f"Bearer {ANON_KEY}"
}

# select=* se saare columns aayenge, limit=1 se sirf ek record aayega test ke liye
url = f"{SUPABASE_URL}/rest/v1/{TABLE_NAME}?select=*&limit=1"

response = requests.get(url, headers=headers)
print(response.text)