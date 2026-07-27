"""
صفحه چت - همیار نجات
--------------------------------------------------------------------------
مسیر: HamyarNejat_Package/app/pages/1_Chat.py
"""

import os
import sys

import streamlit as st

current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from core.preprocess import preprocess_query
from core.retrieve import (
    retrieve_context,
    stream_response_with_history,
    RetrievalError,
    GenerationError,
)
from core.history import (
    create_new_session,
    get_session_data,
    add_message_to_session,
    delete_session,
    get_valid_sessions,
)
from core.config import check_ollama_ready

# نوار کناری سفارشی اختیاری است؛ اگر موجود نبود برنامه نباید متوقف شود.
try:
    from core.ui_utils import setup_custom_sidebar
except ImportError:
    setup_custom_sidebar = None

st.set_page_config(page_title="چت با همیار", page_icon="logo.png", layout="centered")


# ===========================================================================
# فونت محلی
# فونت باید از فایل محلی بارگذاری شود. نسخه قبلی فونت را از cdn.jsdelivr.net
# می‌گرفت که روی یک سیستم آفلاین هرگز بارگذاری نمی‌شود و فقط باعث تأخیر و
# به‌هم‌ریختن تایپوگرافی فارسی می‌شد.
# فایل فونت را در این مسیر قرار دهید:
#   HamyarNejat_Package/app/assets/Vazirmatn-Regular.woff2
# ===========================================================================
@st.cache_data(show_spinner=False)
def _load_local_font_css() -> str:
    import base64

    font_path = os.path.join(parent_dir, "assets", "Vazirmatn-Regular.woff2")
    if not os.path.isfile(font_path):
        return ""  # به فونت Tahoma سیستم برمی‌گردیم
    try:
        with open(font_path, "rb") as fh:
            b64 = base64.b64encode(fh.read()).decode("utf-8")
    except Exception:
        return ""
    return f"""
@font-face {{
    font-family: 'Vazirmatn';
    src: url(data:font/woff2;base64,{b64}) format('woff2');
    font-weight: normal;
    font-display: swap;
}}
"""


st.markdown(
    f"""
<style>
{_load_local_font_css()}

html, body, p, div, h1, h2, h3, h4, h5, h6, a, button, input, textarea, select {{
    font-family: 'Vazirmatn', Tahoma, sans-serif !important;
}}

/* راست‌چین کردن لیبل دراپ‌داون */
[data-testid="stSelectbox"] label {{
    direction: rtl !important;
    text-align: right !important;
    width: 100% !important;
    display: block !important;
}}
[data-testid="stSelectbox"] div[data-baseweb="select"] {{
    direction: rtl !important;
    text-align: right !important;
}}

/* نوار کناری */
[data-testid="stSidebarNav"] {{ display: none !important; }}
[data-testid="stSidebarUserContent"] {{ direction: rtl; text-align: right; }}

/* باکس ورودی چت */
div[data-testid="stChatInput"] textarea {{
    direction: rtl !important;
    text-align: right !important;
}}
div[data-testid="stChatInput"] {{ direction: rtl !important; }}

/* حذف آواتارها */
.stChatMessageAvatar,
[data-testid="chatAvatarIcon-user"],
[data-testid="chatAvatarIcon-assistant"] {{
    display: none !important;
}}

/* کانتینر پیام‌ها */
[data-testid="stChatMessage"] {{
    direction: rtl !important;
    text-align: right !important;
}}
[data-testid="stChatMessageContent"],
[data-testid="stMarkdownContainer"],
[data-testid="stMarkdownContainer"] > p,
[data-testid="stMarkdownContainer"] > ul,
[data-testid="stMarkdownContainer"] > ol {{
    direction: rtl !important;
    text-align: right !important;
}}

/* پیام‌های خطا و هشدار راست‌چین */
[data-testid="stAlert"] {{
    direction: rtl !important;
    text-align: right !important;
}}

/* انیمیشن انتظار — کاملاً CSS، بدون هیچ درخواست شبکه‌ای.
   نسخه قبلی یک GIF از giphy.com بارگذاری می‌کرد که آفلاین کار نمی‌کند. */
.hn-thinking {{
    display: flex; flex-direction: row-reverse; align-items: center; gap: 6px;
    padding: 6px 2px; direction: rtl;
}}
.hn-thinking span {{
    width: 8px; height: 8px; border-radius: 50%;
    background-color: #b00020; display: inline-block;
    animation: hn-bounce 1.2s infinite ease-in-out both;
}}
.hn-thinking span:nth-child(2) {{ animation-delay: -0.16s; }}
.hn-thinking span:nth-child(3) {{ animation-delay: -0.32s; }}
@keyframes hn-bounce {{
    0%, 80%, 100% {{ transform: scale(0.6); opacity: 0.5; }}
    40%           {{ transform: scale(1.0); opacity: 1.0; }}
}}

/* مکان‌نمای چشمک‌زن هنگام تولید متن */
.hn-cursor {{
    display: inline-block; width: 7px; background-color: currentColor;
    animation: hn-blink 1s step-end infinite; margin-right: 2px;
}}
@keyframes hn-blink {{ 50% {{ opacity: 0; }} }}
</style>
""",
    unsafe_allow_html=True,
)

if setup_custom_sidebar:
    setup_custom_sidebar()

st.title("چت با همیار نجات")

category = st.selectbox(
    "حوزه سوال خود را انتخاب کنید (جهت جستجوی دقیق تر):",
    ["فوریت‌های روانشناسی", "فوریت‌های فنی", "فوریت‌های امدادی", "فوریت‌های پزشکی"],
    index=3,
)

st.divider()


# ===========================================================================
# نوار کناری: وضعیت موتور محلی + تاریخچه
# ===========================================================================
with st.sidebar:
    if not setup_custom_sidebar:
        st.page_link("app.py", label="صفحه اصلی", icon="🏠")
        st.page_link("pages/1_Chat.py", label="چت بات", icon="💬")
        st.page_link("pages/2_Articles.py", label="مقالات", icon="📚")
        st.divider()

    # وضعیت موتور محلی. اگر Ollama خاموش باشد، کاربر پیش از تایپ کردن
    # سوال متوجه می‌شود — به جای دیدن یک traceback انگلیسی بعد از انتظار.
    engine_ok, engine_msg = check_ollama_ready()
    if engine_ok:
        st.caption("🟢 موتور محلی آماده است")
    else:
        st.error(f"🔴 {engine_msg}")

    st.divider()
    st.header("تاریخچه چت‌ها")

    if st.button("➕ شروع چت جدید", use_container_width=True):
        st.session_state.current_session_id = create_new_session(title=category)
        st.rerun()

    st.divider()

    sessions = get_valid_sessions()
    sorted_sessions = sorted(
        sessions.items(), key=lambda x: x[1]["timestamp"], reverse=True
    )

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


# ===========================================================================
# نشست جاری
# ===========================================================================
if (
    "current_session_id" not in st.session_state
    or st.session_state.current_session_id is None
):
    st.session_state.current_session_id = create_new_session(title=category)

current_sess = get_session_data(st.session_state.current_session_id)
messages = current_sess["messages"] if current_sess else []

for message in messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])


# ===========================================================================
# چرخه پرسش و پاسخ
# ===========================================================================
THINKING_HTML = '<div class="hn-thinking"><span></span><span></span><span></span></div>'

if prompt := st.chat_input("سوال یا مشکل خود را اینجا بنویسید..."):

    st.chat_message("user").markdown(prompt)
    add_message_to_session(
        st.session_state.current_session_id, "user", prompt, title=category
    )

    with st.chat_message("assistant"):
        placeholder = st.empty()
        placeholder.markdown(THINKING_HTML, unsafe_allow_html=True)

        # -------------------------------------------------------------------
        # ۱. بازیابی اطلاعات از پایگاه دانش
        #    شکست بازیابی دیگر بی‌صدا نیست. اگر پایگاه دانش در دسترس نباشد،
        #    کاربر باید بداند که پاسخ بر پایه منابع تأییدشده نیست.
        # -------------------------------------------------------------------
        context = ""
        retrieval_failed = False

        try:
            processed_query = preprocess_query(prompt)
            context = retrieve_context(processed_query, category)

        except RetrievalError as err:
            retrieval_failed = True
            placeholder.empty()
            st.error(f"⚠️ {err.message}")
            # جزئیات فنی فقط به کنسول می‌رود، نه به کاربر نهایی.
            print(f"[RetrievalError] {err.technical_detail}")

        except Exception as err:  # هر خطای پیش‌بینی‌نشده
            retrieval_failed = True
            placeholder.empty()
            st.error("⚠️ خطای غیرمنتظره هنگام جستجو در پایگاه دانش.")
            print(f"[Unexpected retrieval error] {err}")

        if retrieval_failed:
            st.info(
                "پاسخ زیر تنها بر پایه دانش عمومی مدل تولید می‌شود و "
                "به منابع تأییدشده همیار نجات دسترسی ندارد."
            )
            placeholder = st.empty()
            placeholder.markdown(THINKING_HTML, unsafe_allow_html=True)

        elif not context:
            st.warning(
                "در دسته‌بندی انتخاب‌شده مطلب مرتبطی یافت نشد. "
                "شاید دسته دیگری مناسب‌تر باشد."
            )
            placeholder = st.empty()
            placeholder.markdown(THINKING_HTML, unsafe_allow_html=True)

        # -------------------------------------------------------------------
        # ۲. تولید پاسخ به صورت جریانی
        #    متن به تدریج نمایش داده می‌شود. اگر تولید در میانه راه شکست
        #    بخورد، بخش تولیدشده حفظ و ذخیره می‌شود.
        # -------------------------------------------------------------------
        updated_sess = get_session_data(st.session_state.current_session_id)
        history_msgs = updated_sess["messages"][:-1] if updated_sess else []

        full_response = ""
        generation_failed = False

        try:
            for token in stream_response_with_history(prompt, context, history_msgs):
                full_response += token
                placeholder.markdown(
                    full_response + '<span class="hn-cursor">&nbsp;</span>',
                    unsafe_allow_html=True,
                )

            placeholder.markdown(full_response)

        except GenerationError as err:
            generation_failed = True
            if full_response:
                placeholder.markdown(full_response)
            else:
                placeholder.empty()
            st.error(f"⚠️ {err.message}")
            print(f"[GenerationError] {err.technical_detail}")

        except Exception as err:
            generation_failed = True
            if full_response:
                placeholder.markdown(full_response)
            else:
                placeholder.empty()
            st.error("⚠️ خطای غیرمنتظره هنگام تولید پاسخ.")
            print(f"[Unexpected generation error] {err}")

    # -----------------------------------------------------------------------
    # ۳. ذخیره پاسخ
    #    پاسخ ناقص هم ذخیره می‌شود تا تاریخچه با آنچه کاربر دید یکسان بماند.
    # -----------------------------------------------------------------------
    if full_response.strip():
        if generation_failed:
            full_response += "\n\n_(این پاسخ به دلیل بروز خطا ناقص است.)_"
        add_message_to_session(
            st.session_state.current_session_id, "assistant", full_response
        )
