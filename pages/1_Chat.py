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
from core.ui_utils import setup_custom_sidebar, get_base64_of_bin_file

st.set_page_config(page_title="چت با همیار", page_icon="logo.png", layout="centered")

setup_custom_sidebar()

# تزریق ایمن کدهای CSS برای راست‌چین کردن متن‌ها و حفظ آواتارها
st.markdown("""
<style>
@import url('https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css');

html, body, p, div, h1, h2, h3, h4, h5, h6, a, button, input, textarea, select {
    font-family: 'Vazirmatn', sans-serif !important;
}

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

chat_icon_path = os.path.join(parent_dir, "icon_chat.png")
chat_b64 = get_base64_of_bin_file(chat_icon_path)
icon_html = f'<img src="data:image/png;base64,{chat_b64}" style="width: 40px; margin-left: 10px;">' if chat_b64 else ""

icon_add_path = os.path.join(parent_dir, "icon_add.png")
icon_add_b64 = get_base64_of_bin_file(icon_add_path)
icon_add_mime = "image/png"
if not icon_add_b64:
    svg_add = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#666666" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>'
    import base64
    icon_add_b64 = base64.b64encode(svg_add.encode('utf-8')).decode('utf-8')
    icon_add_mime = "image/svg+xml"

icon_delete_path = os.path.join(parent_dir, "icon_delete.png")
icon_delete_b64 = get_base64_of_bin_file(icon_delete_path)
icon_delete_mime = "image/png"
if not icon_delete_b64:
    svg_delete = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#666666" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>'
    import base64
    icon_delete_b64 = base64.b64encode(svg_delete.encode('utf-8')).decode('utf-8')
    icon_delete_mime = "image/svg+xml"

st.markdown(f"""
<style>
/* New Chat button */
div.stElementContainer:has(#marker-new-chat) + div.stElementContainer button p::before,
div[data-testid="stElementContainer"]:has(#marker-new-chat) + div[data-testid="stElementContainer"] button p::before,
div[data-testid="element-container"]:has(#marker-new-chat) + div[data-testid="element-container"] button p::before {{
    content: "";
    display: inline-block;
    width: 28px;
    height: 28px;
    background-image: url("data:{icon_add_mime};base64,{icon_add_b64}");
    background-size: contain;
    background-repeat: no-repeat;
    margin-left: 10px; /* Used margin-left because the layout is RTL and it pushes text to the right */
    vertical-align: middle;
}}

/* Delete Chat buttons */
[data-testid="stSidebar"] div[data-testid="column"]:nth-of-type(2) button,
[data-testid="stSidebar"] div[data-testid="stColumn"]:nth-of-type(2) button {{
    background-image: url("data:{icon_delete_mime};base64,{icon_delete_b64}");
    background-color: transparent !important;
    background-size: 20px 20px;
    background-repeat: no-repeat;
    background-position: center;
    border: none !important;
    width: 100% !important;
    height: 100% !important;
    min-height: 40px;
    box-shadow: none !important;
    color: transparent !important;
}}
[data-testid="stSidebar"] div[data-testid="column"]:nth-of-type(2) button:hover,
[data-testid="stSidebar"] div[data-testid="stColumn"]:nth-of-type(2) button:hover {{
    background-color: rgba(255, 0, 0, 0.1) !important;
}}
[data-testid="stSidebar"] div[data-testid="column"]:nth-of-type(2) button p,
[data-testid="stSidebar"] div[data-testid="stColumn"]:nth-of-type(2) button p {{
    display: none;
}}
</style>
""", unsafe_allow_html=True)

st.markdown(f"""
<div style="display: flex; align-items: center; justify-content: flex-start; direction: rtl; margin-bottom: 20px;">
    {icon_html}
    <h1 style="margin: 0; padding: 0;">چت با همیار نجات</h1>
</div>
""", unsafe_allow_html=True)

category = st.selectbox(
    "حوزه سوال خود را انتخاب کنید (جهت جستجوی دقیق تر):",
    ["فوریت‌های روانشناسی", "فوریت‌های فنی", "فوریت‌های امدادی", "فوریت‌های پزشکی"],
    index=3
)

st.divider()

# سایدبار برای تاریخچه (بدون هیچ‌گونه کد CSS اضافه)
with st.sidebar:
    st.divider()
    
    st.header("تاریخچه چت‌ها")
    st.markdown("<div id='marker-new-chat'></div>", unsafe_allow_html=True)
    if st.button("شروع چت جدید", use_container_width=True):
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
            if st.button("\u200B", key=f"del_{sess_id}"):
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
