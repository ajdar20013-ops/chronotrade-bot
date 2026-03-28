import asyncio
import logging
import sqlite3
import os
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import ReplyKeyboardMarkup, KeyboardButton, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.utils.keyboard import InlineKeyboardBuilder

TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
DB_NAME = 'chronotrade.db'

logging.basicConfig(level=logging.INFO)

# --- БАЗА ДАННЫХ ---
def init_db():
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            user_id INTEGER PRIMARY KEY,
            name TEXT,
            skill TEXT,
            balance REAL DEFAULT 1.0
        )
    ''')
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS offers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            description TEXT,
            cost REAL,
            emotional_load TEXT,
            status TEXT DEFAULT 'active'
        )
    ''')
    conn.commit()
    conn.close()

def get_user(user_id):
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE user_id = ?", (user_id,))
    user = cursor.fetchone()
    conn.close()
    return user

def add_user(user_id, name, skill):    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("INSERT OR IGNORE INTO users (user_id, name, skill) VALUES (?, ?, ?)", (user_id, name, skill))
    conn.commit()
    conn.close()

def add_offer(user_id, description, cost, emotional_load):
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO offers (user_id, description, cost, emotional_load) VALUES (?, ?, ?, ?)", 
                   (user_id, description, cost, emotional_load))
    conn.commit()
    conn.close()

def get_all_offers():
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM offers WHERE status = 'active'")
    offers = cursor.fetchall()
    conn.close()
    return offers

class RegisterState(StatesGroup):
    name = State()
    skill = State()

class OfferState(StatesGroup):
    description = State()
    emotional_load = State()

bot = Bot(token=TOKEN)
dp = Dispatcher()

def get_main_keyboard():
    kb = [
        [KeyboardButton(text="📝 Создать предложение"), KeyboardButton(text="🔎 Найти помощь")],
        [KeyboardButton(text="📊 Мой баланс")]
    ]
    return ReplyKeyboardMarkup(keyboard=kb, resize_keyboard=True)

def get_emotional_keyboard():
    builder = InlineKeyboardBuilder()
    builder.button(text="🔋 Заряжает", callback_data="emo_charge")
    builder.button(text="😐 Нейтрально", callback_data="emo_neutral")
    builder.button(text="🪫 Тратит силы", callback_data="emo_drain")
    return builder.as_markup()

@dp.message(Command("start"))
async def cmd_start(message: types.Message, state: FSMContext):
    user = get_user(message.from_user.id)    if not user:
        await message.answer(
            "🌍 Добро пожаловать в **ChronoTrade**!\n\n"
            "Это биржа времени нового поколения.\n"
            "Валюта — твои часы. Гарант — ИИ.\n\n"
            "Напиши своё имя для старта:",
            parse_mode="Markdown"
        )
        await state.set_state(RegisterState.name)
    else:
        await message.answer(
            f"С возвращением в **ChronoTrade**, {user[1]}! ⏳\n"
            f"Твой баланс: {user[3]} часов.",
            reply_markup=get_main_keyboard(),
            parse_mode="Markdown"
        )

@dp.message(RegisterState.name)
async def process_name(message: types.Message, state: FSMContext):
    await state.update_data(name=message.text)
    await message.answer("Какой навык ты предлагаешь? (например: Психология, Дизайн):")
    await state.set_state(RegisterState.skill)

@dp.message(RegisterState.skill)
async def process_skill(message: types.Message, state: FSMContext):
    data = await state.get_data()
    add_user(message.from_user.id, data['name'], message.text)
    await state.clear()
    await message.answer(
        "✅ Профиль активирован!\n"
        "🎁 **Бонус:** +1 час страхового времени.",
        reply_markup=get_main_keyboard()
    )

@dp.message(F.text == "📊 Мой баланс")
async def show_balance(message: types.Message):
    user = get_user(message.from_user.id)
    if not user:
        await message.answer("Сначала нажмите /start")
        return
    
    insight = "🚀 Активно торгуйте временем!" if user[3] > 2 else "⚠️ Создайте первое предложение."
    
    await message.answer(
        f"📊 **Портфель ChronoTrade**\n\n"
        f"⏳ Баланс: {user[3]} ч.\n"
        f"🧠 Навык: {user[2]}\n\n"
        f"💡 **AI-Совет:** {insight}",
        parse_mode="Markdown"
    )
@dp.message(F.text == "📝 Создать предложение")
async def start_create_offer(message: types.Message, state: FSMContext):
    user = get_user(message.from_user.id)
    if not user:
        await message.answer("Сначала нажмите /start")
        return
    await message.answer("Что вы готовы сделать? (Опишите задачу):")
    await state.set_state(OfferState.description)

@dp.message(OfferState.description)
async def process_offer_desc(message: types.Message, state: FSMContext):
    await state.update_data(description=message.text)
    await message.answer(
        "⚖️ **Оцените нагрузку:**\nЭто вас заряжает или тратит силы?",
        reply_markup=get_emotional_keyboard()
    )
    await state.set_state(OfferState.emotional_load)

@dp.callback_query(OfferState.emotional_load)
async def process_emotional_load(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    data = await state.get_data()
    
    emotional_map = {
        "emo_charge": ("🔋 Заряжает", 0.8),
        "emo_neutral": ("😐 Нейтрально", 1.0),
        "emo_drain": ("🪫 Тратит силы", 1.5)
    }
    
    load_name, coefficient = emotional_map[callback.data]
    final_cost = 1.0 * coefficient
    
    await state.clear()
    add_offer(callback.from_user.id, data['description'], final_cost, load_name)
    
    await callback.message.answer(
        f"✅ **Предложение опубликовано!**\n\n"
        f"📝 Задача: {data['description']}\n"
        f"⚡ Нагрузка: {load_name}\n"
        f"💰 Цена: {final_cost} ч.",
        parse_mode="Markdown"
    )

@dp.message(F.text == "🔎 Найти помощь")
async def find_help(message: types.Message):
    offers = get_all_offers()
    if not offers:
        await message.answer("🕸️ Пока нет активных предложений.\nСтаньте первым!")
        return    
    text = "🔎 **Лента предложений:**\n\n"
    for offer in offers:
        author = get_user(offer[1])
        name = author[1] if author else "Аноним"
        text += f"👤 **{name}**\n"
        text += f"📝 {offer[2]}\n"
        text += f"⚡ {offer[4]} | 💰 {offer[3]} ч.\n"
        text += "------------------\n"
    
    await message.answer(text, parse_mode="Markdown")

async def main():
    init_db()
    await dp.start_polling(bot)

if __name__ == '__main__':
    asyncio.run(main())
