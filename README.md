<div align="center">

<img src="logo2.png" alt="NeuroBench" width="120" />

# NeuroBench

**Бенчмарк-платформа для оценки генеративных LLM**

*Генерация · Логика · Визуальный интеллект*

[![Live](https://img.shields.io/badge/Live-Site-222?logo=github&style=flat-square)](https://moonishe.github.io/NB/)
[![Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase&style=flat-square)](https://supabase.com)
[![Telegram](https://img.shields.io/badge/Telegram-Auth-26A5E4?logo=telegram&style=flat-square)](https://telegram.org)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

</div>

---

```
 _   _                       ____                  _
| \ | | ___ _   _ _ __ ___  | __ )  ___ _ __   ___| |__
|  \| |/ _ \ | | | '__/ _ \ |  _ \ / _ \ '_ \ / __| '_ \
| |\  |  __/ |_| | | | (_) || |_) |  __/ | | | (__| | | |
|_| \_|\___|\__,_|_|  \___/ |____/ \___|_| |_|\___|_| |_|
```

## ▸ Что это

**NeuroBench** — open-source платформа для оценки генеративных моделей через визуальные и логические задачи.  
Даём LLM холст или код — получаем результат. Лидерборд, форум, профили, ачивки — всё в одном месте.

🔗 **[Открыть сайт](https://moonishe.github.io/NB/)**

---

## ▸ Бенчмарки

| Модуль | Что проверяем | Статус |
|--------|---------------|--------|
| 🟦 **SVG Bench** | Пространственное мышление, координаты, структура SVG-кода | [Активен](https://moonishe.github.io/NB/svg.html) |
| 🟢 **Shader Bench** | Цвет, свет, фрагментные вычисления, GLSL-логика | [Активен](https://moonishe.github.io/NB/shader.html) |
| 🔵 **Voxel Bench** | 3D-структуры, объём, кубические преобразования | В разработке |

---

## ▸ Фичи

```
┌──────────────────────────────────────────────────┐
│                                                  │
│   🏆 Лидерборды     — рейтинг моделей по задачам │
│   💬 Форум          — обсуждение и подходы       │
│   👤 Профили        — история, ачивки, инвайты   │
│   ✈️  Telegram Auth  — вход через Telegram       │
│   🛡️ Админ-панель   — модерация и аналитика     │
│   ⭐ 25+ ачивок     — за участие и активность    │
│   🔒 Invite-only    — закрытая регистрация        │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## ▸ Архитектура

```
  ┌───────────────────────┐
  │     GitHub Pages      │
  │   (Static Frontend)   │
  │  index · svg · shader │
  │  forum · profile      │
  └──────────┬────────────┘
             │ HTTPS
             ▼
  ┌───────────────────────┐
  │       Supabase        │
  │  ┌─────────────────┐  │
  │  │   PostgreSQL    │  │
  │  │     (Data)      │  │
  │  └────────┬────────┘  │
  │           │           │
  │  ┌────────▼────────┐  │
  │  │  Edge Functions │  │
  │  │    (Deno/TS)     │  │
  │  │ · telegram-auth │  │
  │  │ · admin-action  │  │
  │  │ · turnstile     │  │
  │  └────────┬────────┘  │
  └──────────┼────────────┘
             │
             ▼
  ┌───────────────────────┐
  │     Telegram API      │
  │  Login Widget + Bot   │
  └───────────────────────┘
```

---

## ▸ Стек

| Слой | Технология |
|------|------------|
| Frontend | Vanilla HTML/JS, Tailwind CSS, Geist Mono + Inter |
| Backend | Supabase (PostgreSQL + Edge Functions) |
| Auth | Telegram Login Widget + Turnstile + Supabase Auth |
| Хостинг | GitHub Pages |

---

## ▸ Запуск

```bash
git clone https://github.com/Moonishe/NB.git
cd NB
npx serve .
# → http://localhost:3000
```

---

## ▸ Структура

```
├── index.html          ← Главная (лидерборд)
├── svg.html            ← SVG бенчмарк
├── shader.html         ← Shader бенчмарк
├── voxel.html          ← Voxel бенчмарк
├── forum.html          ← Форум
├── profile.html        ← Профиль
├── register.html       ← Авторизация
├── admin/              ← Админ-панель
├── js/                 ← Фронтенд-модули
├── css/                ← Стили (dark terminal)
├── supabase/           ← Edge Functions + SQL-миграции
└── assets/             ← Ачивки, вендоры
```

---

## ▸ Деплой

- **GitHub Pages**: Settings → Pages → Branch `main` / root
- **Supabase**: Edge Functions в `supabase/functions/`, миграции в `supabase/*.sql`

---

<div align="center">

*NeuroBench* — benchmarking the future of generative AI

</div>
