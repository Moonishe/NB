# NeuroBench

> **Бенчмарк платформа для LLM. Генерация, логика, визуальный интеллект.**

[![Live](https://img.shields.io/badge/GitHub%20Pages-Live-222?logo=github)](https://moonishe.github.io/NB/)
[![Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase)](https://supabase.com)
[![Telegram](https://img.shields.io/badge/Telegram-Auth-26A5E4?logo=telegram)](https://telegram.org)

---

## Что это

**NeuroBench** — платформа для оценки генеративных моделей через визуальные и логические задачи. Даём LLM холст или код, получаем результат. Лидерборд, форум, профили, ачивки — всё в одном месте.

## Модули

| Бенчмарк | Что проверяем |
|----------|---------------|
| **SVG Bench** | Пространственное мышление, координаты, структура SVG |
| **Shader Bench** | Цвет, свет, фрагментные вычисления, GLSL-логика |
| **Voxel Bench** | 3D-структуры, объём, кубические преобразования |

## Фичи

- **Лидерборды** — рейтинг моделей по каждому бенчмарку
- **Форум** — обсуждение результатов и подходов
- **Профили** — история, ачивки, инвайт-система
- **Telegram Auth** — вход через Telegram
- **Админ-панель** — модерация и аналитика
- **Achievements** — 25+ ачивок за участие
- **Invite-only** — закрытая регистрация

## Стек

| Слой | Технология |
|------|------------|
| Frontend | Vanilla HTML/JS, Tailwind CSS, Geist Mono + Inter |
| Backend | Supabase (PostgreSQL + Edge Functions) |
| Auth | Telegram Login Widget + Supabase Auth |
| Хостинг | GitHub Pages |

## Запуск

```bash
git clone https://github.com/Moonishe/NB.git
cd NB
npx serve .
# http://localhost:3000
```

## Структура

```
├── index.html          # Главная (SVG лидерборд)
├── svg.html            # SVG бенчмарк
├── shader.html         # Shader бенчмарк
├── voxel.html          # Voxel бенчмарк
├── forum.html          # Форум
├── profile.html        # Профиль
├── register.html       # Авторизация
├── admin/              # Админ-панель
├── js/                 # Модули фронтенда
├── css/                # Стили (dark terminal)
├── supabase/           # Edge Functions + миграции
└── assets/             # Ачивки, вендоры
```

## Деплой

**GitHub Pages**: Settings → Pages → Branch `main` / root  
**Supabase**: Edge Functions в `supabase/functions/`, миграции в `supabase/*.sql`

## Лицензия

MIT
