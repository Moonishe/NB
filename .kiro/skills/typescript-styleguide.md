---
name: TypeScript Style Guide
description: TypeScript coding standards and patterns
inclusion: manual
---

# TypeScript Style Guide

## Типизация
- Предпочитай явные типы для публичных API
- Используй `interface` для объектов и `type` для объединений
- Избегай `any`, используй `unknown` если тип неизвестен

## Примеры:
```typescript
// Интерфейс vs Type
interface User {
  id: string;
  name: string;
}

type Status = 'pending' | 'active' | 'completed';

// Generic-функция
function getFirst<T>(arr: T[]): T | undefined {
  return arr[0];
}
```

## Обработка ошибок
- Используй Error Boundaries для React
- Все async функции должны обрабатывать ошибки

## Именование
- Интерфейсы: PascalCase (UserService)
- Константы: UPPER_SNAKE_CASE
- Функции: camelCase