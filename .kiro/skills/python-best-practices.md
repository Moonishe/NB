---
name: Python Best Practices
description: Guidelines for writing clean Python code
inclusion: manual
---

# Python Best Practices для Kiro

## Стиль кода
- Используй snake_case для переменных и функций
- Используй PEP 8 руководство по стилю
- Длина строки не более 79 символов

## Типизация
- Всегда добавляй type hints для функций
- Используй typing модуль для сложных типов

## Пример:
```python
from typing import List, Optional

def process_items(items: List[str], max_items: Optional[int] = None) -> List[str]:
    """Обрабатывает список строк."""
    if max_items:
        return items[:max_items]
    return items
```

## Тестирование
- Пиши тесты с использованием pytest
- Используй fixtures для подготовки данных