import os
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()
url = os.environ.get("SUPABASE_URL")
key = os.environ.get("SUPABASE_KEY")
supabase: Client = create_client(url, key)

# Tumhare terminal se uthayi hui exact missing students ki list
missing_data = {
    "9%Girl": ['Insharah', 'Arooj Shaukat', 'Hareem', 'Annaya'],
    "11%Girl": ['Abeera khawar', 'Mehreen Mustafa', 'Jawahir Sajjad', 'Ajiya'],
    "11%Boy": ['Shaheer Irfan', 'Mutarib Ali', 'Muhammad Umar', 'M. Hassan Zia', 'Mo Arsal Gul', 'Akhter Zaman', 'Zaman Joiya', 'Abu-bakar', 'Abdul Moiz Ahmed', 'Haseeb Ali'],
    "12%Boy": ['Mudassir Nawaz', 'Ayyan Butt', 'M. Ali', 'M. Mohsin', 'Hasnain Ahmed', 'M. Abdullah Awan'],
    "9%Boy": ['Muhammad Mahad Kiyani', 'Sana Ullah', 'HM Umair Hassaan', 'Syed Ghayur Haider', 'Abdul Maiz', 'Abaidullah Butt', 'Muhammad Waleed', 'Muhammad Azan', 'Muhammad Ayan', 'Muhammad Ibrahim', 'Muhammad Wassi', 'Rayyan Ahmed']
}

def auto_add_students():
    print("🚀 Auto-Adding Missing Students...\n")
    
    batches_res = supabase.table('batches').select('id, name').execute()
    batches = {b['name']: b['id'] for b in batches_res.data}

    for batch_kw, students in missing_data.items():
        batch_id = None
        for b_name, b_id in batches.items():
            parts = batch_kw.split('%')
            if all(p.lower() in b_name.lower() for p in parts):
                batch_id = b_id
                actual_batch_name = b_name
                break
        
        if batch_id:
            records = [{'name': s_name, 'batch_id': batch_id} for s_name in students]
            try:
                supabase.table('students').insert(records).execute()
                print(f"✅ Inserted {len(students)} students in {actual_batch_name}")
            except Exception as e:
                print(f"❌ Error inserting into {actual_batch_name}: {e}")

if __name__ == "__main__":
    auto_add_students()