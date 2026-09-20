import os
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()
url = os.environ.get("SUPABASE_URL")
key = os.environ.get("SUPABASE_KEY")
supabase: Client = create_client(url, key)

# Compressed Attendance Data (1 = 1st Sep, 15 = 17th Sep)
bulk_data = {
    "10%Girl": { "Kinza Irum Noor": "PAPPPPPPPPPPPPP", "Musferah Ehtisham": "APAAPPPAPPPPPPP", "Kalsoom Bibi": "PAAAPAPAPAPAPAP", "Zainab Bibi": "PAPAPPPPPAPPPPP", "Rida Hijab": "PAPAAAAAAAAPPPP", "Amna Bibi": "PAAAPAPPPAPPPPA", "Sundas": "PPPPPPPPPPPAPPP", "Tehreem": "APPPPPPPPPPPAPA", "Mahnoor": "PPPPPPPPPPPPPPP", "Minahil Asghar": "PPPAAAPPPPAAPPP", "Minahil Khan": "PAPPPPAPPPAPPPP", "Khadija": "PAAAPPPPPAAAAAA", "Amna Noor": "AAAAAAAAPPAAAAA", "Eman Siddique": "PPPPPPPPPPPPPPP", "Arooj Fatima": "PPPPPAPAAPAAAAP", "Marriyum": "PPPPPPPPPPPPPPP", "Aiman": "PAPAPPPPPPPAPPP", "Ayesha Batool": "PPAPPPPPPPPAAPP", "Saiqa": "PPPPPPPPPPAAPPP" },
    "9%Girl": { "Abrish Rauf": "AAPPPPPPPPPPPPP", "Anzala Fatima": "PPPPPPPPPPPPPPP", "Zoha Behzad": "AAPPPPPPPPPPPPP", "Fiza Shahzad": "AAPPPPPPPPPPPPP", "Kinz-ul-Eman": "AAAAPPPPPPPPAAA", "Fatima Tuz Zahra": "PPPAPPPPPPPAPPP", "Saba Khanum Jaffari": "PPPPPPPPPPPPPPP", "Bisma Ehtisham": "AAAAAPPPPPPPPPP", "Anaya Noor": "AAAAAPPPPPPAAPA", "Memoona Shaukat": "AAPPPPPPPPAAPPP", "Hamania Shahid": "APPPAPPPPPPPPPP", "Afeen Malik": "AAAAAAPAAAPPPPP", "Fatiha": "PPPPPPPPPPAAAAA", "Ayesha Mariyum": "PPPAAAAAAAAAAAA", "Insharah": "APAAAAAAAAAAAAA", "Arooj Shaukat": "AAAAPPPPPPPPPPP", "Hareem": "AAAAAAAAPPPPPPP", "Annaya": "AAAAAAAAPPPAPPP" },
    "11%Girl": { "Nabira Naveed": "PPPPPPPPPPPPPPP", "Aiman Fatima": "PPAPAAPPPPPPPPP", "Umama Fiaz": "PAPPPPPPPPPPPPP", "Shamayem Choudhary": "PPPPPPPPPPPPPPP", "Zainab": "PPPPPPPPPPPPPPP", "Rameen Fatima": "PAPPPPPPPPPPPPP", "Minahil Fatima": "PPPPPPPPPPPPPPP", "Amna Zubair": "PAPAPAPPPPPPPPP", "Aliysha Fatima": "PPPPAPPPPPPPPPP", "Wania": "PPPPAPAPPPPPPPP", "Afsheen": "PPPPPPAAAPPPPPP", "Farzeen": "PPAPAAAPPAPAAAP", "Fatima Sarfraz": "PPPAPAPPPPPPPPP", "Misbah Javed": "PPAPPAPPPAPPPPP", "Ishmal Ramzan": "PPAPPPPPAPPPPPP", "Abeera khawar": "PPAPPPPPPPPPPPP", "Mehreen Mustafa": "APAAAAAAAAAAAAA", "Jawahir Sajjad": "AAAAAAAAAAAAAPP", "Ajiya": "AAAAAAAAAAAAAAPA" },
    "10%Boy": { "Muhammad Eibad": "APPPAAAAAAAAAAA", "Ahmed Hassan": "APPPPPPPPPPPAPA", "Muhammad Saad": "PPPAAPAPPPPPPPP", "Talha Hashmi": "AAAAPAAAAAAAAAA", "Husnain Ali": "PPPPPPPPPAPAPPP", "Muhammad Qasim": "PPAPPPPPPPAAAPP", "Eibad Ameen": "AAAAAAAPAPPPPPP", "Muhammad Ahmad": "PPPPPPPPPPAPAPP", "Muhammad Taha": "AAAAAAPAPAAAAAA", "Muhammad Abdullah": "PPAAPPPPPPPPPPP", "Arqam Raza": "AAPPPPPPAPAPAPP", "Ibrahim Zahid": "PPPPAAPAAPPPPPP", "Muhammad Shaheer Khalid": "AAAAAPPPPPPPPPP", "Abdul Hadi": "PPPPPAAPPPPAPAP", "M. Abdullah": "PPAAAAAAAAAAAAA" },
    "11%Boy": { "Muhammad Asif": "PAAAAAAAPPPPPPP", "Muhammad Ikram": "PPPPPPPPPPPPPPP", "Adeem Gohar": "PPPPPPPPPPPPPPP", "Muhammad Rauf Khan": "PPPPPPPPPPPAPPP", "Abdullah Yousafzai": "PPPPAPPPPPPPPPP", "Muhammad Hassan Zahid": "AAAAPAPPPPPPPPP", "Zaid Mukhtar": "PPPPPPPPPPPPPPP", "Ahmad Mukhtar": "PPPPPAAPPPPPPPP", "Umer Awan": "AAPAAPAPPPPPPPP", "Muhammad Bin Qasim": "PPPPPPPPPPPPPPP", "Talha Riaz": "AAAPPPPPPPPPPPP", "Attique-ur-Rehman": "APPPPPPPPPPPPPP", "Muhammad Ali Jilani": "PPPPAPPPPPPPPPP", "Abdul Hannan Khan": "AAPPAPAPPPPPPPP", "Asad Khan": "PPPPPPPPPPPPPPP", "Shaheer Irfan": "PPPPPPPPPPPAPPP", "Huzaifa Qasim": "PPPPPPPPPPPPPPP", "Mutarib Ali": "PPAPAPPPPAPPPPP", "Wahaj Usman": "PPPAPPPPPPPPPPP", "Muhammad Mazhar": "PPPAPPPPPPPPPPP", "Samiullah Asif": "PPPPPPPPPPPPPPP", "Muhammad Umar": "PPAPAPPPPPPPPPP", "M. Hassan Zia": "PPPPPAAPPPPPPPP", "Mo Arsal Gul": "AAAPAAPPAPPPAPP", "Fahad Jamil": "PPPPPAPPPPPPPPP", "Akhter Zaman": "PPPPPAPPPPPPPPP", "Zaman Joiya": "PPPPPPPPPPPPPPP", "Abu-bakar": "PAPPPPPPPPPPPPP", "Abdul Moiz Ahmed": "PPPPPPPPPPPPPPP", "Haseeb Ali": "PAAAAAAAAAAAAAA" },
    "12%Girl": { "Zumar Asad": "PPPPPPPPPPPPPPP", "Imama Zubair": "PPPPPPPPPPPPPPP", "Abrish Fatima": "PAPPPPPPPPPPPPP", "Nozaira Fatima": "PPPPPPPPPPPPPPP", "Hifsa Naveed": "PPPPPPPAPPPPPPP", "Fajr Asad": "PPPAPPPPPPPPPPP", "Sara Mirza": "PPPPAPPPPPPPPPP", "Sofia Shoaib": "PPPPPPPPPPPPPPP", "Mashal Rahim": "PPPPPPPPPPPPPPP", "Sara Ali": "PPPPAAPPPPPPPPP", "Hafza Mahnoor": "AAAAPPPPPPPPPPP", "Hijab Imran": "PPPPPPPPPPPPPPP", "Syeda Zahra Naqvi": "PPPPPPPAPPPPPPP", "Ayesha Sabir": "AAAAAPAAPPPPPPP", "Haleema": "PPPPPPPAPPPPPPP", "Seerat": "PPPPPPPPPPPPPPP", "Syeda Shehr Bano": "PPPPPPPPPPPAPAA", "Areesha Shahzad": "PPPAAPPPAPAPPPP", "Areeba": "PPAPAPAPAAPPPPP", "Hajira": "APPPAPAAAPPPAAA", "Qudsia": "PPPPPPPPPPPPPPP", "Gulbashra": "PPPPAAPPAPPAPPP", "Tehreem Khalid": "PPPPPPPPPPPPPPP" },
    "12%Boy": { "Zohair Khan": "PPPAPPPPPPPPPPP", "Mehtab Ahsan": "PPAPAAAPPPPPPPP", "Sohail Farooq": "PPPPPPPPPPPPPPP", "Farzad": "PPPPPPPPPPPPPPP", "Hasnain": "PPPPPPPPPPPPPPP", "Sarib": "PPPPPAAAAAAAAAA", "Abdul Rehman": "PPPPPPPPPPPPPPP", "Hassan Nawaz": "PPPPPPPPPPPPPPP", "Mudassir Nawaz": "PPPPPPPPPPPPPPP", "Ayyan Butt": "PPPPPPPPPPPPPPP", "Kumail": "PPPPPPPPPPPPPPP", "Rayyan": "PAPPAPAAPPPPPPP", "Salman Noor": "PPPPPPPPPPPPPPP", "Rao Saif Ullah": "PPPPPPPPPPPPPPP", "Abdur Raffay": "PPPAPPPPPPPPPPP", "M Abdullah": "PPPPPPPPPPPPPPP", "Uzair Shoukat": "PPPPAPPPPPPPPPP", "Yasir Abbas": "AAAAAAAPPPPPPPP", "M Akbar": "PPPPAAPPPPPPPPP", "Muhammad Junaid": "PAPPPPPPPPPPPPP", "M. Talha": "PPPPPAPPPPPPPPP", "Hadi": "PPPPPAPPPPPPPPP", "M. Ali": "PPPAPAPPPPPPPPP", "M. Mohsin": "AAPPPAPAAPPPPPP", "Hasnain Ahmed": "AAAAAPAAPPPPAAA", "M. Abdullah Awan": "AAAAAAAAAAAPPPP" },
    "9%Boy": { "Muhammad Kaif": "AAPPPPPPPPPPPPP", "Muhammad Ali Raza": "APPPAPPPPPPPPPP", "Saim Sadaqat": "PPPPPPPPPPPPPPP", "Muhammad Haris": "APPPAPPPPPPPPPP", "Muhammad Mahad Kiyani": "APPPAPPPPPPPPPP", "Muhammad Mujtaba": "PPPAPPPPPPPPPPP", "Fawad Siddique": "AAPAAPAPPPPPPPP", "Sana Ullah": "AAAAPPPPPPPPPPP", "Junaid Haider": "PPAPPPPPPPPPPPP", "HM Umair Hassaan": "AAAAPAAAPPPPPPP", "Muhammad Rafi": "AAAPPAAPPPPPPPP", "Muhammad Shaheer": "APPPPPPPPPPPPPP", "Muhammad Zeeshan Shahid": "PPPPPPPPPPPPPPP", "Syed Ghayur Haider": "AAAAPPPPPPPPPPP", "Zulqurnain": "PAPAAAPPPPPPPPP", "Nameer Raza": "AAAAAAPPPPPPPPP", "Hammad Abubakar": "PAAAAAPPPPPPPPP", "Haris Ahmad": "AAAAAAPAPPPPPPP", "Muhammad Usman": "PPAAAAAPPPPPPPP", "Muhammad Abdullah": "PPAAAAPPPPPPPPP", "Muhammad Umar Majid": "PPAAAAPPPPPPPPP", "Abdul Maiz": "PAPPAPPPPPPPPPP", "Talha": "PPPPPPPPPPPPPPP", "Abaidullah Butt": "APAAAAPPPPPPPPP", "Mouavia": "AAAAAAPAPPPPPPP", "Syed Abdul Mateen": "AAAAAAAAAAAPPPP", "Sharoon Arshad": "PAPAAAAAAAAAPPP", "Muhammad Waris": "AAAAAPAAPPPPPPP", "Danial Hussain": "AAAAAAPAPPPPPPP", "Muhammad Waleed": "AAPAPAPPPPPPPPP", "Saqlain": "APAAPPPPPPPPPPP", "Hamza Ajmal": "AAPPPPPPPPPPPPP", "Muhammad Azan": "APPPPPPPPPPPPPP", "Muhammad Ayan": "PPAAPPPPPPPPPPP", "Muhammad Ibrahim": "PPPPAPPPPPPPPPP", "Muhammad Wassi": "PPPAPPPPPPPPPPP", "Rayyan Ahmed": "PPPPPPPPPPPPPPP" }
}

def run_bulk_upload():
    # Exactly 15 dates excluding 6th and 13th (Sundays)
    dates = ['2026-09-01', '2026-09-02', '2026-09-03', '2026-09-04', '2026-09-05',
             '2026-09-07', '2026-09-08', '2026-09-09', '2026-09-10', '2026-09-11',
             '2026-09-12', '2026-09-14', '2026-09-15', '2026-09-16', '2026-09-17']

    print("🚀 Bulk Upload Start Ho Raha Hai...")
    
    batches_res = supabase.table('batches').select('id, name').execute()
    batches = {b['name']: b['id'] for b in batches_res.data}

    for batch_kw, students_dict in bulk_data.items():
        batch_id = None
        for b_name, b_id in batches.items():
            parts = batch_kw.split('%')
            if all(p.lower() in b_name.lower() for p in parts):
                batch_id = b_id
                break

        if not batch_id:
            print(f"❌ Batch nahi mila keyword ke liye: {batch_kw}")
            continue

        print(f"\n🔄 Processing Batch: {batch_kw}")
        db_students_res = supabase.table('students').select('id, name').eq('batch_id', batch_id).execute()
        # Create a lowercase mapping for exact match
        db_students = {s['name'].strip().lower(): s['id'] for s in db_students_res.data}

        records_to_insert = []
        missing_students = []

        for student_name, attendance_str in students_dict.items():
            s_id = db_students.get(student_name.strip().lower())
            
            if not s_id:
                missing_students.append(student_name)
                continue

            # [:15] lagane se ye string ko strictly 15 working days tak lock kar dega
            for i, status_char in enumerate(attendance_str[:15]):
                status_enum = 'present' if status_char == 'P' else 'absent'
                records_to_insert.append({
                    'student_id': s_id,
                    'batch_id': batch_id,
                    'date': dates[i],
                    'status': status_enum
                })

        # Agar hand-written students abhi DB mein nahi daale hue toh script bata degi
        if missing_students:
            print(f"⚠️ Warning! Ye students DB mein nahi mile, pehle inhe add karo: {missing_students}")

        if records_to_insert:
            chunk_size = 500
            for i in range(0, len(records_to_insert), chunk_size):
                chunk = records_to_insert[i:i + chunk_size]
                # upsert se data duplicate nahi hoga
                supabase.table('attendance').upsert(chunk, on_conflict='student_id,date').execute()
            print(f"✅ {len(records_to_insert)} records successfully pushed!")

    print("\n🎉 Bulk Upload Complete!")

if __name__ == "__main__":
    run_bulk_upload()