import os
from dotenv import load_dotenv
from supabase import create_client, Client
import pandas as pd
import dataframe_image as dfi
from datetime import datetime
import warnings
import calendar
import pywhatkit as kit
import time

warnings.filterwarnings('ignore')

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

load_dotenv()
url = os.environ.get("SUPABASE_URL")
key = os.environ.get("SUPABASE_KEY")
supabase: Client = create_client(url, key)

def process_all_batches():
    print("🚀 Master Automation Engine Start Ho Raha Hai...\n")
    
    # Sirf wo batches uthao jinme WhatsApp Group ID set hai
    # Database se sab fetch karo aur Python me filter karo jinka group ID set ho
    batches_res = supabase.table('batches').select('id, name, whatsapp_group_id').execute()
    batches = [b for b in batches_res.data if b.get('whatsapp_group_id') is not None]
    
    if not batches:
        print("❌ Supabase me koi aesa batch nahi mila jiska 'whatsapp_group_id' set ho.")
        return

    now = datetime.now()
    year, month = now.year, now.month
    _, last_day = calendar.monthrange(year, month)
    
    start_date = f"{year}-{month:02d}-01"
    end_date = f"{year}-{month:02d}-{last_day:02d}"
    valid_days = [d for d in range(1, last_day + 1) if datetime(year, month, d).weekday() != 6]
    month_name = now.strftime('%b %Y')

    for index, batch in enumerate(batches):
        batch_id = batch['id']
        batch_name = batch['name']
        group_id = batch['whatsapp_group_id']
        
        print(f"[{index+1}/{len(batches)}] 🔄 Processing Batch: {batch_name}")
        
        students_res = supabase.table('students').select('id, name').eq('batch_id', batch_id).order('name').execute()
        students_data = students_res.data
        
        if not students_data:
            print(f"⚠️ Skipping {batch_name}: Koi students nahi hain.\n")
            continue

        df_students = pd.DataFrame(students_data)
        df_students['Sr No'] = df_students.index + 1
        df_students.rename(columns={'name': 'Name of Student'}, inplace=True)

        att_res = supabase.table('attendance').select('student_id, date, status').eq('batch_id', batch_id).gte('date', start_date).lte('date', end_date).execute()
        attendance_data = att_res.data

        if not attendance_data:
            df_att = pd.DataFrame(columns=['student_id', 'date', 'status'])
        else:
            df_att = pd.DataFrame(attendance_data)

        if not df_att.empty:
            df = pd.merge(df_students, df_att, left_on='id', right_on='student_id', how='left')
            status_map = {'present': 'P', 'absent': 'A', 'leave': 'L'}
            df['status_short'] = df['status'].map(status_map)
            
            df_valid_dates = df.dropna(subset=['date']).copy()
            df_valid_dates['day'] = pd.to_datetime(df_valid_dates['date']).dt.day.astype(int)
            pivot_df = df_valid_dates.pivot(index='Name of Student', columns='day', values='status_short')
        else:
            pivot_df = pd.DataFrame(index=df_students['Name of Student'])

        df_final = df_students[['Sr No', 'Name of Student']].merge(pivot_df, on='Name of Student', how='left')

        for d in valid_days:
            if d not in df_final.columns:
                df_final[d] = ''
                
        columns_order = ['Sr No', 'Name of Student'] + valid_days
        df_final = df_final[columns_order]
        df_final = df_final.fillna('')

        styles = [
            {"selector": "table", "props": [("border-collapse", "collapse"), ("border", "2px solid black"), ("min-width", "1250px")]},
            {"selector": "th", "props": [("border", "1px solid black !important"), ("padding", "10px 15px"), ("background-color", "#f0f0f0"), ("text-align", "center")]},
            {"selector": "td", "props": [("border", "1px solid black !important"), ("padding", "10px 15px"), ("text-align", "center")]},
            {"selector": "tbody tr", "props": [("background-color", "white !important")]},
            {"selector": "td:nth-child(2)", "props": [("text-align", "left"), ("white-space", "nowrap"), ("padding-left", "15px"), ("min-width", "250px")]},
            {"selector": "caption", "props": [("caption-side", "top"), ("text-align", "center"), ("margin-bottom", "20px"), ("color", "black")]}
        ]

        caption_html = (
            f"<span style='font-size: 22px; font-weight: bold;'>FGEIs Evening Coaching Classes</span>"
            f"<hr style='border: 0; border-top: 2px solid black; margin: 10px 0;'>"
            f"<span style='font-size: 22px; font-weight: bold;'>Attendance Report for Month of {month_name} for {batch_name}</span>"
        )

        styled_df = df_final.style.set_table_styles(styles).set_caption(caption_html).hide(axis="index")

        filename = f"{batch_name.replace(' ', '_')}_Attendance.png"
        image_path = os.path.join(BASE_DIR, filename)
        dfi.export(styled_df, image_path, max_cols=-1, max_rows=-1)
        print("✅ Image Rendered.")

        # WhatsApp Send Logic
        caption_text = f"Assalam o Alaikum,\nAttached is the automated attendance report for {batch_name} ({month_name})."
        print("📲 Forwarding to WhatsApp Group...")
        
        try:
            # wait_time 20 seconds is safe for slow internet.
            kit.sendwhats_image(
                receiver=group_id,
                img_path=image_path,
                caption=caption_text,
                wait_time=20,
                tab_close=True,
                close_time=5
            )
            print(f"✅ Sent to group {batch_name} successfully!\n")
            
            # Additional 5-second buffer between batches to avoid browser overlap issues
            time.sleep(5) 
        except Exception as e:
            print(f"❌ Error sending to {batch_name}: {e}\n")

    print("🎉 All Batches Processed Successfully!")

if __name__ == "__main__":
    process_all_batches()