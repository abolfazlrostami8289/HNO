import streamlit as st
import sys
import os

current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from core.preprocess import preprocess_query
from core.retrieve import retrieve_context, generate_response_with_history
from core.history import create_new_session, get_session_data, add_message_to_session, delete_session, get_valid_sessions

st.set_page_config(page_title="چت با همیار", page_icon="logo.png", layout="centered")

# تزریق ایمن کدهای CSS برای راست‌چین کردن متن‌ها و حفظ آواتارها
st.markdown("""
<style>
/* راستچین کردن لیبل دراپداون */
[data-testid="stSelectbox"] label {
    direction: rtl !important;
    text-align: right !important;
    width: 100% !important;
    display: block !important;
}

/* راستچین کردن متن داخل خود باکس دراپداون */
[data-testid="stSelectbox"] div[data-baseweb="select"] {
    direction: rtl !important;
    text-align: right !important;
}

/* Sidebar Custom Nav */
[data-testid="stSidebarNav"] { display: none !important; }
[data-testid="stSidebarUserContent"] { direction: rtl; text-align: right; }

/* راستچین کردن باکس ورودی چت */
div[data-testid="stChatInput"] textarea {
    direction: rtl !important;
    text-align: right !important;
}
div[data-testid="stChatInput"] {
    direction: rtl !important;
}

/* حذف آیکونها و آواتارهای کاربر و هوش مصنوعی */
.stChatMessageAvatar, 
[data-testid="chatAvatarIcon-user"], 
[data-testid="chatAvatarIcon-assistant"] {
    display: none !important;
}

/* راستچین کردن کانتینر اصلی پیامها */
[data-testid="stChatMessage"] {
    direction: rtl !important;
    text-align: right !important;
}

/* راستچین کردن قطعی محتوای متنی، پاراگرافها و لیستها */
[data-testid="stChatMessageContent"], 
[data-testid="stMarkdownContainer"], 
[data-testid="stMarkdownContainer"] > p,
[data-testid="stMarkdownContainer"] > ul,
[data-testid="stMarkdownContainer"] > ol {
    direction: rtl !important;
    text-align: right !important;
    font-family: 'Vazirmatn', sans-serif !important;
}
</style>
""", unsafe_allow_html=True)

st.title("چت با همیار نجات")

category = st.selectbox(
    "حوزه سوال خود را انتخاب کنید (جهت جستجوی دقیق تر):",
    ["فوریت‌های روانشناسی", "فوریت‌های فنی", "فوریت‌های امدادی", "فوریت‌های پزشکی"],
    index=3
)

st.divider()

# سایدبار برای تاریخچه (بدون هیچ‌گونه کد CSS اضافه)
with st.sidebar:
    st.page_link("app.py", label="صفحه اصلی", icon="🏠")
    st.page_link("pages/1_Chat.py", label="چت بات", icon="💬")
    st.page_link("pages/2_Articles.py", label="مقالات", icon="📚")
    
    st.divider()
    
    st.header("تاریخچه چت‌ها")
    if st.button("➕ شروع چت جدید", use_container_width=True):
        st.session_state.current_session_id = create_new_session(title=category)
        st.rerun()
        
    st.divider()
    
    sessions = get_valid_sessions()
    sorted_sessions = sorted(sessions.items(), key=lambda x: x[1]['timestamp'], reverse=True)
    
    for sess_id, sess_data in sorted_sessions:
        button_label = sess_data["title"]
        for msg in sess_data.get("messages", []):
            if msg["role"] == "user":
                content = msg["content"]
                button_label = content[:25] + "..." if len(content) > 25 else content
                break
                
        col1, col2 = st.columns([4, 1])
        with col1:
            if st.button(button_label, key=f"load_{sess_id}", use_container_width=True):
                st.session_state.current_session_id = sess_id
                st.rerun()
        with col2:
            if st.button("❌", key=f"del_{sess_id}"):
                delete_session(sess_id)
                if st.session_state.get("current_session_id") == sess_id:
                    st.session_state.current_session_id = None
                st.rerun()

if "current_session_id" not in st.session_state or st.session_state.current_session_id is None:
    st.session_state.current_session_id = create_new_session(title=category)

current_sess = get_session_data(st.session_state.current_session_id)
messages = current_sess["messages"] if current_sess else []

for message in messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

if prompt := st.chat_input("سوال یا مشکل خود را اینجا بنویسید..."):
    st.chat_message("user").markdown(prompt)
    add_message_to_session(st.session_state.current_session_id, "user", prompt, title=category)

    with st.chat_message("assistant"):
        placeholder = st.empty()
        placeholder.markdown("""
            <img src="https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExNHJ4ZzNqZ3J4ZzNqZ3J4ZzNqZ3J4ZzNqZ3J4ZzNqJmVwPXYxX2ludGVybmFsX2dpZl9ieV9pZCZjdD1n/l41lTjJp8yYyG2bkc/giphy.gif" 
            width="50" style="border-radius: 50%;">
        """, unsafe_allow_html=True)
            
        processed_query = preprocess_query(prompt)
        context = retrieve_context(processed_query, category)
        
        updated_sess = get_session_data(st.session_state.current_session_id)
        history_msgs = updated_sess["messages"][:-1] if updated_sess else []
        
        response = generate_response_with_history(prompt, context, history_msgs)
        
        placeholder.empty()
        st.markdown(response)
            
    add_message_to_session(st.session_state.current_session_id, "assistant", response)
