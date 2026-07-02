#!/bin/bash

# --- НАСТРОЙКИ ---
# Количество одновременных проверок. Подберите оптимальное значение для вашей системы.
# Начните с 10-20 и увеличьте, если у вас мощный процессор и быстрый интернет.
MAX_JOBS=50

# Таймаут для проверки одного моста в секундах.
TIMEOUT=40

# Пути к файлам (можно изменить)
TORRC_FILE="/etc/tor/torrc"
BRIDGES_FILE="bridges-obfs4.txt"
OUTPUT_FILE="working_bridges.txt"
LOG_FILE="bridge_check.log"

# --- КОНЕЦ НАСТРОЕК ---

# Функция для корректного выхода по Ctrl+C
trap "echo -e '\nПрерывание работы. Очистка...'; exit 1" SIGINT SIGTERM

# Очистка старых файлов
> "$OUTPUT_FILE"
> "$LOG_FILE"

# Функция извлечения мостов из torrc
extract_from_torrc() {
    grep -E '^Bridge\s+obfs4' "$TORRC_FILE" | sed 's/^Bridge\s\+//'
}

# Функция проверки одного моста. Эта функция будет выполняться в параллель.
# Она полностью изолирована и не конфликтует с другими экземплярами.
check_bridge() {
    local bridge="$1"
    local temp_dir="/tmp/tor-check-$RANDOM"
    local tor_log="$temp_dir/tor_output.log"

    trap "rm -rf '$temp_dir'" RETURN

    mkdir -p "$temp_dir"
    chown tor:tor "$temp_dir"
    chmod 700 "$temp_dir"

    timeout "$TIMEOUT" tor \
        --UseBridges 1 \
        --Bridge "$bridge" \
        --Log "notice stdout" \
        --DataDirectory "$temp_dir" \
        --SocksPort auto \
        --CircuitBuildTimeout 30 \
        > "$tor_log" 2>&1

    if grep -q "Bootstrapped 100%" "$tor_log"; then
        echo "✅ [$bridge] — РАБОТАЕТ"
        echo "$bridge" >> "$OUTPUT_FILE"
    else
        echo "❌ [$bridge] — НЕ РАБОТАЕТ"

        {
            echo "===== [$bridge] ====="
            cat "$tor_log"
            echo "====================="
        } >> "$LOG_FILE"
    fi

    rm -rf "$temp_dir"
}
# Экспортируем функцию, чтобы она была доступна в дочерних процессах, созданных xargs
export -f check_bridge
export TIMEOUT OUTPUT_FILE LOG_FILE

# Выбор источника мостов
echo "Выберите источник мостов:"
echo "1) Из файла $TORRC_FILE"
echo "2) Из файла $BRIDGES_FILE"
read -p "Введите 1 или 2: " source_choice

case $source_choice in
    1)
        if [ ! -f "$TORRC_FILE" ]; then
            echo "Ошибка: Файл $TORRC_FILE не найден!" | tee -a "$LOG_FILE"
            exit 1
        fi
        BRIDGES=$(extract_from_torrc)
        ;;
    2)
        if [ ! -f "$BRIDGES_FILE" ]; then
            echo "Ошибка: Файл $BRIDGES_FILE не найден!" | tee -a "$LOG_FILE"
            exit 1
        fi
        BRIDGES=$(grep -v '^#' "$BRIDGES_FILE" | grep 'obfs4')
        ;;
    *)
        echo "Неверный выбор. Выход." | tee -a "$LOG_FILE"
        exit 1
        ;;
esac

if [ -z "$BRIDGES" ]; then
    echo "В указанном источнике не найдено мостов obfs4!" | tee -a "$LOG_FILE"
    exit 1
fi

TOTAL_BRIDGES=$(echo "$BRIDGES" | wc -l)
echo "Найдено мостов для проверки: $TOTAL_BRIDGES" | tee -a "$LOG_FILE"
echo "Начало параллельной проверки ($MAX_JOBS потоков)..." | tee -a "$LOG_FILE"

# --- Магия параллелизма ---
# 1. printf "%s\n" "$BRIDGES": Безопасно выводит каждый мост на новой строке.
# 2. xargs:
#    -n 1: Передавать в команду по одному аргументу (одному мосту).
#    -P $MAX_JOBS: Запускать максимум $MAX_JOBS процессов параллельно.
#    -I {}: Заменять {} на переданный аргумент.
# 3. bash -c '...': Выполнять нашу функцию check_bridge в новом bash.
#    Мы передаем мост как аргумент, а не через переменные окружения,
#    чтобы избежать проблем со спецсимволами.
# 4. tee -a "$LOG_FILE": Сохраняет весь вывод (и от успешных, и от неуспешных проверок) в лог.
printf "%s\n" "$BRIDGES" | xargs -n 1 -P "$MAX_JOBS" -I {} bash -c 'check_bridge "{}"' | tee -a "$LOG_FILE"

echo -e "\nГотово! Рабочие мосты сохранены в файл: $OUTPUT_FILE" | tee -a "$LOG_FILE"
echo "Лог работы скрипта: $LOG_FILE"
