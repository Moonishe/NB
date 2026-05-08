# NeuroBench

> **Бенчмарк платформа для LLM. Генерация, логика, визуальный интеллект.**

[![Live](https://img.shields.io/badge/GitHub%20Pages-Live-222?logo=github)](https://moonishe.github.io/NB/)
[![Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase)](https://supabase.com)
[![Telegram](https://img.shields.io/badge/Telegram-Auth-26A5E4?logo=telegram)](https://telegram.org)
[![SVG Bench](https://img.shields.io/badge/SVG%20Bench-Active-FF6B6B?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiI+PHJlY3Qgd2lkdGg9IjE2IiBoZWlnaHQ9IjE2IiByeD0iMiIgZmlsbD0iI2ZmZmZmZiIvPjwvc3ZnPg==)](https://moonishe.github.io/NB/svg.html)
[![Shader Bench](https://img.shields.io/badge/Shader%20Bench-Active-4ECDC4?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiI+PGNpcmNsZSBjeD0iOCIgY3k9IjgiIHI9IjgiIGZpbGw9IiNmZmZmZmYiLz48L3N2Zz4=)](https://moonishe.github.io/NB/shader.html)
[![Voxel Bench](https://img.shields.io/badge/Voxel%20Bench-Active-45B7D1?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiI+PHBhdGggZD0iTTIgMmgxMnYxMkgyeiIgZmlsbD0iI2ZmZmZmZiIvPjwvc3ZnPg==)](https://moonishe.github.io/NB/voxel.html)

---

## Что это

**NeuroBench** — платформа для оценки генеративных моделей через визуальные и логические задачи. Даём LLM холст или код, получаем результат. Лидерборд, форум, профили, ачивки — всё в одном месте.

## Модули

| Бенчмарк | Что проверяем |
|----------|---------------|
| **SVG Bench** | Пространственное мышление, координаты, структура SVG |
| **Shader Bench** | Цвет, свет, фрагментные вычисления, GLSL-логика |
| **Voxel Bench** | 3D-структуры, объём, кубические преобразования |

## Скриншоты

> **TODO:** Добавить GIF/скриншоты
>
> Рекомендуем записать через ShareX/OBS → конвертировать в GIF через ffmpeg:
> ```bash
> ffmpeg -i input.mp4 -vf "fps=30,scale=720:-1:flags=lanczos" -c:v gif output.gif
> ```

| Главная (лидерборд) | Форум | Профиль |
|---|---|---|
| `![main](docs/screenshots/main.gif)` | `![forum](docs/screenshots/forum.gif)` | `![profile](docs/screenshots/profile.gif)` |

## Архитектура

```
┌─────────────────────┐
│   GitHub Pages      │
│   (Static Frontend) │
│   index.html        │
│   svg.html          │
│   shader.html       │
│   voxel.html        │
│   forum.html        │
└──────────┬──────────┘
           │ HTTPS
           ▼
┌─────────────────────┐
│      Supabase       │
│  ┌───────────────┐  │
│  │  PostgreSQL   │  │
│  │  (Data)       │  │
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ Edge Functions│  │
│  │ (Deno/TS)     │  │
│  │ - telegram-auth│  │
│  │ - admin-action │  │
│  └───────┬───────┘  │
└──────────┼──────────┘
           │
           ▼
┌─────────────────────┐
│  Telegram API       │
│  (Login Widget +    │
│   Bot Auth)         │
└─────────────────────┘
```

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
