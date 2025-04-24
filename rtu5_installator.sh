#!/usr/bin/env bash

# set -euo pipefail

# цветовые переменные для вывода
NOFORMAT='\033[0m' 
RED='\033[0;31m' 
GREEN='\033[0;32m' 
B_GREEN='\033[1;92m' 
ORANGE='\033[0;33m' 
BLUE='\033[0;34m' 
CYAN='\033[0;36m' 
YELLOW='\033[1;33m' 
TURQUOISE='\033[1;96m'
L_TURQUOISE='\033[0;96m'

# проверка на запуск с правами суперпользователя
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ ERROR ]${NOFORMAT} Скрипт должен запускаться с правами root."
    exit 1
fi

# установить правильный PATH для root (если переход произошел некорректно)
changing_path=$(grep ENV_SUPATH /etc/login.defs | sed -n '2p' | cut --delimiter '=' -f2)
if [ "$(whoami)" == 'root' ]; then
    export PATH=$changing_path
fi

# создание директории для лицензий (если её нет)
LICENSE_DIR="/usr/share/rtu5_installator/licenses"
if [ ! -d "$LICENSE_DIR" ]; then
    mkdir -p "$LICENSE_DIR"
fi

# подключение файла переменных, если он существует
VARS_FILE="/usr/share/rtu5_installator/vars_installator.sh"
if [ -f "$VARS_FILE" ]; then
    source "$VARS_FILE"
fi

# отключение графических окон при установке через apt
DEBIAN_FRONTEND=readline

# конфигурация APT для автоматического подтверждения установок
apt_conf="$(cat <<-EOM
APT {
  Get {
    Assume-Yes "true";
    Fix-Broken "true";
  };
};
EOM
)"

# упрощённые правила iptables
iptables_rules="$(cat <<-EOM
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:mgmt_access - [0:0]
:mysql_access - [0:0]
-A INPUT -p tcp -m tcp --dport 3306 -j mysql_access
-A INPUT -p tcp -m tcp --dport 9000 -j mgmt_access
-A mgmt_access -s 127.0.0.1/32 -j ACCEPT
-A mgmt_access -j REJECT --reject-with icmp-port-unreachable
-A mysql_access -s 127.0.0.1/32 -j ACCEPT
-A mysql_access -j REJECT --reject-with icmp-port-unreachable
COMMIT
EOM
)"

# стандартный список репозиториев Debian 10 Buster
buster_repolist="$(cat <<-EOM
deb http://deb.debian.org/debian buster main contrib non-free
deb-src http://deb.debian.org/debian buster main contrib non-free
deb http://deb.debian.org/debian buster-updates main contrib non-free
deb-src http://deb.debian.org/debian buster-updates main contrib non-free
deb http://archive.debian.org/debian buster-backports main contrib non-free
deb-src http://archive.debian.org/debian buster-backports main contrib non-free
deb http://security.debian.org/debian-security/ buster/updates main contrib non-free
deb-src http://security.debian.org/debian-security/ buster/updates main contrib non-free
EOM
)"

# файл конфига для запросов api mtt
mtt_api_config="$(cat << EOM
#!/usr/bin/env php
<?php

\$contextOptions = array(
        'ssl' => array(
        'verify_peer'   => false,
        'verify_peer_name'  => false,
        'allow_self_signed' => true
    )
);
\$sslContext = stream_context_create(\$contextOptions);

\$options = array('cache_wsdl' => WSDL_CACHE_NONE,
                 'stream_context' => \$sslContext);

\$client = new SoapClient('https://0.0.0.0:8445/service/?wsdl_v2', \$options);

\$headers = array();
\$headers[] = new SoapHeader('auth','Login','yourlogin');
\$headers[] = new SoapHeader('auth','Password','yourpassword');
\$client->__setSoapHeaders(\$headers);

# функция insertRowset для того, чтобы добавить запись в таблицу для колонки Название в Модули ПКком
echo \$client->insertRowset(
        '08.2601.01',
        array(
                array(
                        array(
                                'name' => 'name',
                                'value' => 'sipproxy-MOA-1'
                        )       # добавить тип ноды

                )
        )
);

# функция insertRowset для того, чтобы добавить запись в таблицу для колонки Название в Группы балансировки исх. SIP-трафика
echo \$client->insertRowset(
        '08.2636.01',
        array(
                array(
                        array(
                                'name' => 'proxy_balancing_group_name',
                                'value' => 'subscriber-logic'
                        )

                )
        )
);

# функция insertRowset для того, чтобы добавить запись в таблицу для колонки Название в Группы балансировки вх. SIP-трафика
echo \$client->insertRowset(
        '08.2636.03',
        array(
                array(
                        array(
                                'name' => 'sig_balancing_group_name',
                                'value' => 'subscriber-logic'
                        )

                )
        )
);

# функция updateRowset для того, чтобы обновить запись в таблице для колонки ключ шифрования в Глобальная конфигурация (sipproxy-MOA-1)
\$filter = array(
    'type' => 'cond',
    'column' => 'name',
    'operator' => '=',
    'value' => 'sipproxy-MOA-1'
);
\$result = \$client->selectRowset('08.2601.01', \$filter);
\$node_id = \$result->item->item[0]->value;

\$params = array(
        array('name' => 'node_ids', 'value' => \$node_id)
);

\$filter = array(
    'type' => 'cond',
    'column' => 'proxy_global_name',
    'operator' => 'like',
    'value' => 'new'
);
echo \$client->updateRowset(
    '08.2621.01',
    array(
            array(
                    array(
                            'name' => 'secret',
                            'value' => 'secret-hash-mtt'
                    )

            )
    ),
    \$filter,
    \$params
);

# функция updateRowset для того, чтобы обновить запись в таблице для колонки Включена в Модули балансировки SIP-Функции (sipproxy-MOA-1)
\$filter = array(
    'type' => 'cond',
    'column' => 'module',
    'operator' => '=',
    'value' => 'SPTopologyHiding'
);
echo \$client->updateRowset(
    '08.2631.01',
    array(
            array(
                    array(
                            'name' => 'enable',
                            'value' => '1'
                    )

            )
    ),
    \$filter,
    \$params
);

# функция insertRowset для того, чтобы добавить запись в таблицу для колонки ip-адреса TCP в Принимающих сокетах (sipproxy-MOA-1)
echo \$client->insertRowset(
    '08.2624.01',
    array(
            array(
                    array(
                        'name' => 'listener_uri',
                        'value' => '0.0.0.0:5060'
                    ),
                    array(
                        'name' => 'listener_proto',
                        'value' => 'TCP'
                    )
            )
    ),
    \$params
);

# функция insertRowset для того, чтобы добавить запись в таблицу для колонки ip-адреса UDP в Принимающих сокетах (sipproxy-MOA-1)
echo \$client->insertRowset(
        '08.2624.01',
        array(
                array(
                        array(
                            'name' => 'listener_uri',
                            'value' => '0.0.0.0:5060'
                        ),
                        array(
                            'name' => 'listener_proto',
                            'value' => 'UDP'
                        )
                )
        ),
        \$params
);

# функция insertRowset для того, чтобы добавить запись в таблицу для колонки ip-адреса  localhost UDP в Принимающих сокетах (sipproxy-MOA-1)
echo \$client->insertRowset(
        '08.2624.01',
        array(
                array(
                        array(
                            'name' => 'listener_uri',
                            'value' => '127.0.0.1:5060'
                        ),
                        array(
                            'name' => 'listener_proto',
                            'value' => 'UDP'
                        )
                )
        ),
        \$params
);

# функция insertRowset для того, чтобы добавить запись в таблицу для колонки ip-адреса  localhost UDP в Принимающих сокетах (sipproxy-MOA-1)
echo \$client->insertRowset(
        '08.2624.01',
        array(
                array(
                        array(
                            'name' => 'listener_uri',
                            'value' => '0.0.0.0:5059'
                        ),
                        array(
                            'name' => 'listener_proto',
                            'value' => 'WSS'
                        )
                )
        ),
        \$params
);

# функция insertRowset для того, чтобы добавить запись в таблицу для колонки Модули балансировки SIP-Замена полей в вызовах (не доделан)
\$params = array(
        array('name' => 'node_ids', 'value' => \$node_id),
        array('name' => 'flag_via_and_recordroute_hiding', 'value' => 0),
        array('name' => 'flag_passerted_or_remotepartyid_encode', 'value' => 0)
         );

\$filter = array(
'type' => 'cond',
'column' => 'flag_contact_encode',
'operator' => '=',
'value' => '0'
);

\$result_update = \$client->updateRowset(
'08.2640.01',
array(
  array(
      array('name' => 'flag_contact_encode', 'value' => '1'),
      array('name' => 'flag_change_from_address', 'value' => '2')
       )
   ),
\$filter,
\$params
);

?>
EOM
)"

# объявление переменной для пути откуда запускается скрипт
rtu_working_dir=$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)
rtu_distribution=$(ls -la "${rtu_working_dir}" | grep _amd64.sh | awk '{print $9}')

# список функций ниже

# проверка dns
function check_dns() {
    ping -c 3 ya.ru > /dev/null
	if [ $(echo $?) != 0 ]; then
		echo -e "${RED}[ ERROR ]${NOFORMAT} Не настроены DNS-серверы. Пожалуйста, проверьте ваш узел на доступность DNS."
		exit 1
	else
		echo -e "${GREEN}[ INFO ]${NOFORMAT} DNS настроены корректно, продолжаем установку."
	fi
}

# проверка репозиториев
function check_repos() {
    echo -e "⌛ Проверка доступности репозиториев для установки пакетов."

	ping -c 3 deb.debian.org > /dev/null
	if [ $(echo $?) != 0 ]; then
		echo -e "${RED}[ ERROR ]${NOFORMAT} Нет доступа к ресурсам репозиториев Debian. Пожалуйста, используйте версию РТУ с заранее установленными пакетами или попробуйте поставить эти пакеты любым удобным для вас способом."
		exit 1
	else
		echo -e "${GREEN}[ INFO ]${NOFORMAT} Репозитории Debian доступны для установки необходимых пакетов. Начинаестся установка базовых пакетов для работы."
		echo "${buster_repolist}" > /etc/apt/sources.list
	fi
}

# место создания файла логгирования всей установки
function set_log_dir() {
	while true
	do
		echo -ne "${BLUE}[ VALUE ]${NOFORMAT} Укажите директорию (в формате абсолютного пути), куда будет сохранен лог-файл установки или просто нажмите enter и файл будет сохранен там же, откуда запущен инсталлятор: "
		read log_file_dir_choice
		case ${log_file_dir_choice} in
			'')
				echo -e "${GREEN}[ INFO ]${NOFORMAT} Лог-файл установки будет сохранен в директорию по умолчанию."
				log_file_dir="$rtu_working_dir"
				break
			;;
			*)
				ls "${log_file_dir_choice}" &> /dev/null
				if [[ $(echo $?) != 0 ]]; then
					echo -ne "${RED}[ ERROR ]${NOFORMAT} Вы ввели несуществующую директорию. Хотите повторить ваш ввод заново или оставить значение по умолчанию?
1) Ввести значение директории заново
2) Оставить значение по умолчанию
Введите ваш выбор: "
					read log_file_dir_choice_repeat
					case ${log_file_dir_choice_repeat} in
						'1')
							echo -e "${GREEN}[ INFO ]${NOFORMAT} Вы выбрали повторный ввод диреткории для сохраниения файла."
						;;
						'2')
							echo -e "${GREEN}[ INFO ]${NOFORMAT} Вы выбрали значение по умолчанию. Лог-файл установки будет сохранен в директорию по умолчанию."
							log_file_dir="$rtu_working_dir"
							break
						;;
						*)
							input_error
						;;
					esac
				else
					log_file_dir="$log_file_dir_choice"
					echo -e "${GREEN}[ INFO ]${NOFORMAT} Лог-файл установки будет сохранен в указанную вами директорию: ${log_file_dir}"
					break
				fi
			;;
		esac
	done
}

# Пример настройки iptables
function setup_iptables() {
    echo "$iptables_rules" > /etc/iptables_rules
    iptables-restore < /etc/iptables_rules
    echo -e "${GREEN}[ INFO ]${NOFORMAT} Правила iptables настроены."
}

# проверка зависимостей и установка необходимых пакетов
function install_dependencies() {
    echo -e "${BLUE}[ INFO ]${NOFORMAT} Проверяем необходимые пакеты"
    packages=(sudo curl ntp net-tools unzip mc expect dnsutils)

    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -qw "$pkg"; then
            echo -e "${YELLOW}[ INFO ]${NOFORMAT} Устанавливаем $pkg"
            apt install -y "$pkg"
        else
            echo -e "${GREEN}[ OK ]${NOFORMAT} Пакет $pkg уже установлен."
        fi
    done
}

# настройка DNS-серверов (пример обработки)
function configure_dns() {
    echo -e "${BLUE}[ INFO ]${NOFORMAT} Настройка DNS"
    read -p "Введите адрес DNS-сервера: " dnsaddress

    if [[ $dnsaddress =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "nameserver $dnsaddress" > /etc/resolv.conf
        echo -e "${GREEN}[ INFO ]${NOFORMAT} DNS успешно настроен."
    else
        echo -e "${RED}[ ERROR ]${NOFORMAT} Введён некорректный IP-адрес DNS."
        configure_dns
    fi
}

# настройка NTP-синхронизации
function configure_ntp() {
    echo -e "${BLUE}[ INFO ]${NOFORMAT} Настройка NTP"
    service ntp stop
    ntpdate -q pool.ntp.org
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[ ERROR ]${NOFORMAT} Ошибка синхронизации с NTP-сервером. Проверьте DNS или подключение."
    else
        service ntp start
        echo -e "${GREEN}[ INFO ]${NOFORMAT} Время успешно синхронизировано."
    fi
}

# ошибка ввода
function input_error() {
	echo -e "${RED}[ ERROR ]${NOFORMAT} Вы ввели недопустимое значение для данного выбора, введите значение заново." 
}

# выход из скрипта
function power_off() {
	echo -e "${GREEN}[ INFO ]${NOFORMAT} Вы выбрали выход из программы, установка прекращена."
	exit 0
}

# сборка архива с информацией о системе для получения лицензии
function create_license_archive() {
	while true
	do
		echo -ne "${BLUE}[ VALUE ]${NOFORMAT} Для подготовки архива укажите наименование вашей компании: "
		read company_name
		if [ -z "${company_name}" ]; then
			echo -e "${RED}[ ERROR ]${NOFORMAT} Вы ввели пустое значение, введите значение заново."
		else
			echo -e "${GREEN}[ INFO ]${NOFORMAT} Записывается указанное вами имя компании ${company_name} в файл company_info."
			echo ${company_name} > company_info
			dmidecode > dmidecode_$(hostname) && ip a > ip_$(hostname) && tar cjf $(hostname)_$(date +"%m-%d-%Y").tar.bz2 dmidecode_$(hostname) ip_$(hostname) company_info && rm dmidecode_$(hostname) ip_$(hostname) company_info
			archive_dir=$(pwd)
			echo -e "${GREEN}[ INFO ]${NOFORMAT} Ниже описана важная информация:
${YELLOW} ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${NOFORMAT}
${YELLOW}│${NOFORMAT}${L_TURQUOISE} Архив .tar.bz2 с необходимыми данными для выпуска программной лицензии располагается в директории: your_pwd_directory                  ${YELLOW}│${NOFORMAT}                  
${YELLOW}│${NOFORMAT}${L_TURQUOISE} Отправьте полученный архив на e-mail адрес license@your_mail.org, в теме письма укажите наименование вашей компании.                   ${YELLOW}│${NOFORMAT}                 
${YELLOW}│${NOFORMAT}${L_TURQUOISE} После установки программной лицензии потребуется активация программной лицензии. Для активации следуйте инструкции в ответном письме.  ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}${L_TURQUOISE} Запросы на выпуск программной лицензии обрабатываются в рабочие дни с 08:00 до 17:00.                                                  ${YELLOW}│${NOFORMAT}                                              
${YELLOW}│${NOFORMAT}${L_TURQUOISE} При возникновении вопросов оформите запрос на сайте технической поддержки https://helpdesk.org                                         ${YELLOW}│${NOFORMAT}
${YELLOW} ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${NOFORMAT}"                               
			echo 
			echo -e "${GREEN}[ INFO ]${NOFORMAT} Разместите полученные файлы программной лицензии в директории /usr/share/rtu5_installator/licenses
${GREEN}[ INFO ]${NOFORMAT} По готовности повторно запустите сценарий rtu5_installator.sh с аргументом -A"
			break
		fi
	done
}

# проверка на существование пакета dmidecode в системе
function check_dmidecode() {
	echo -e "${GREEN}[ INFO ]${NOFORMAT} Проверка на наличие в системе пакета dmidecode для подготовки архива."
	if dpkg-query -W -f='${Status}' dmidecode 2>/dev/null | grep -q "install ok installed"; then
		echo -e "${GREEN}[ INFO ]${NOFORMAT} Пакет dmidecode существует в системе ✅ !"
	else
		echo -e "${RED}[ ERROR ]${NOFORMAT} Пакет dmidecode не найден в системе. Попытка установки пакета dmidecode ⌛"
		ping -c 3 ya.ru > /dev/null
		if [ $(echo $?) != 0 ]; then
			echo -e "${RED}[ ERROR ]${NOFORMAT} Не настроены DNS-серверы. Пожалуйста, проверьте ваш узел на доступность DNS."
			exit 1
		else
			echo -e ""
		fi
		ping -c 3 deb.debian.org > /dev/null
		if [ $(echo $?) != 0 ]; then
			echo -e "${RED}[ ERROR ]${NOFORMAT} Нет доступа к ресурсам репозиториев Debian. Пожалуйста, используйте версию РТУ с заранее установленными пакетами или попробуйте поставить эти пакеты любым удобным для вас способом."
			exit 1
		else
			echo -e ""
			echo "${buster_repolist}" > /etc/apt/sources.list
		fi
		apt install -y dmidecode > /dev/null
		if [ $(echo $?) != 0 ]; then
			echo -e "${RED}[ ERROR ]${NOFORMAT} Пакет dmidecode не установился или установился не корректно в вашей системе. \nПопробуйте установить его вручную, после чего запустите инсталлятор с аргументом -T"
			exit 1
		else
		echo -e "${GREEN}[ INFO ]${NOFORMAT} Пакет dmidecode успешно установлен ✅ !"
		fi
	fi
}

# мини-инструкция по взаимодействию со скриптом установки
function usage() {
echo -e "${YELLOW}
 ─────────────────────────────────────────────────── Инсталлятор РТУ, односерверный ───────────────────────────────────────────────────────────
${YELLOW}│                                                           краткое описание                                                                   ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}                                                                                                                                              ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Ознакомтесь, пожалуйста, с данной инструкцией и укажите необходимый аргумент при запуске инсталлятора.                                       ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}                                                                                                                                              ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Данный скрипт запускает автоматическую установку и конфигурацию РТУ 2.3*, запрашивая у вас необходимые данные.                               ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Он сконфигурирует и настроит оставшиеся компоненты системы.                                                                                  ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}                                                                                                                                              ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Если у вас имеются файлы абоненсткой лицензии и ключа, расположите их, пожалуйста, в директории ${TURQUOISE} [ /usr/share/rtu5_installator/licenses ]    ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} и перезапустите rtu5_installator.sh с аргуменом -A.                                                                                          ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}                                                                                                                                              ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Вам будет представлена работа в интерактивном режиме по нижесказанным основным пунктам:                                                      ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} ${BLUE}──────────────────────────────────────────────────────────────────────────────────────────────────────${NOFORMAT}                                       ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Пункт 1. Настройка сети для работы и конфигурация файла system-1.zone.conf                                                                   ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Пункт 2. Установка пакетов, настройка сервера доменных имен DNS и сервиса синхронизации времени NTP                                          ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Пункт 3. Настройка iptables, ttyrec, snoopy и проброс портов                                                                                 ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Пункт 4. Установка компонентов РТУ (ts, web-cfg, logic-cfg, centrex, examples)                                                               ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Пункт 5. Проверка наличия и установки файлов программного ключа и абонетской лицензии                                                        ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Пункт 6. Настройка компонентов подсистемы коммутации                                                                                         ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Пункт 7. Проверка чтения ключа и выполнение конфигурации                                                                                     ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} ${BLUE}──────────────────────────────────────────────────────────────────────────────────────────────────────${NOFORMAT}                                       ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Этот скрипт обязательно нужно выполнять с правами суперпользователя root.                                                                    ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}                                                                                                                                              ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Вам доступны следующие аргументы для выполнения скрипта:                                                                                     ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}                                                                                                                                              ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} ${B_GREEN} -A${NOFORMAT} (ALL)      Установка всех 7-ми компонетов                                                                                                ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} ${B_GREEN} -T${NOFORMAT} (.tar.bz2) Подготовка архива с данными для получения лицензии                                                                            ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}                                                                                                                                              ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} В процессе работы вам будут задаваться вопросы и предложения для ввода неких значений, которые скрипт будет обрабатывать.                    ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT} Они будут выглядеть как показано ниже:                                                                                                       ${YELLOW}│${NOFORMAT}
${YELLOW}│${NOFORMAT}                                                                                                                                              ${YELLOW}│${NOFORMAT}
${YELLOW}│ ${GREEN}[ INFO ]${NOFORMAT} - вывод системы несущий в себе сугубо информационный характер                                                                       ${YELLOW}│${NOFORMAT}
${YELLOW}│ ${RED}[ ERROR ]${NOFORMAT} - ошибки системы и ввода пользователя при работе со скриптом                                                                       ${YELLOW}│${NOFORMAT}
${YELLOW}│ ${ORANGE}[ QUESTION ]${NOFORMAT} - предложение о выборе некоего значения из представленного списка                                                               ${YELLOW}│${NOFORMAT}
${YELLOW}│ ${BLUE}[ VALUE ]${NOFORMAT} - предложение о вводе значения                                                                                                     ${YELLOW}│${NOFORMAT}
${YELLOW} ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
${NOFORMAT}"
}

# настройка сети и выбор ipv4 для работы скрипта
function configure_network() {	
echo -e "${YELLOW}
───────────────────────────────────────── Пункт 1 ───────────────────────────────────────────
│${B_GREEN}                                  Настройка сети для работы                                  ${YELLOW}│ 
│${B_GREEN}                          и конфигурация файла system-1.zone.conf                            ${YELLOW}│
─────────────────────────────────────────────────────────────────────────────────────────────${NOFORMAT}"
if [ -f "/usr/share/rtu5_installator/vars_installator.sh" ]; then
    echo -e "${GREEN}[ INFO ]${NOFORMAT} Пункт 1 уже выполнился ранее. Переход к 2 пункту."
else
    # проверяем наличие и количество ipv4 адресов на сетевых интерфейсах
    ip_count=$(ip a | grep --invert-match 127.0.0.1 | cut -d '/' -f1 | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | wc --lines)
    # пользователь выбирает ip адрес из списка доступных
    case ${ip_count} in
        # Адресов нет - сообщение сконфигурируйте сеть - выход
        '0')
            echo -e "${RED}[ ERROR ]${NOFORMAT} IPv4 адресов не обнаружено. Требуется конфигурация сети."
            exit 1
        ;;
        # Присутствует единственный ip адрес 
        '1')
            adapter=$(ip -br l | awk '$1 !~ "lo|vir|wl" { print $1}')
            echo -e "${GREEN}[ INFO ]${NOFORMAT} Выбранный сетевой интерфейс для работы: ${adapter}"
            ip=$(ip addr show ${link} | grep --invert-match 127.0.0.1/8 | egrep 'inet ' | awk '{print $2}' | cut --delimiter '/' -f1)
            echo -e "${GREEN}[ INFO ]${NOFORMAT} Выбранный IPv4-адрес для работы: ${ip}"
            #sed --in-place 's|XXX.XXX.XXX.0|'${ip}'|' /usr/share/rtu5_configurator/.preconf/system-1.zone.conf
        ;;
        # Присутствует несколько ip адресов
        *)   
            echo -e "${GREEN}[ INFO ]${NOFORMAT} Ниже выведен список доступных IP-адресов для данного сервера: "
            declare -a ip_addrs_array=($(ip addr show ${link} | grep --invert-match 127.0.0.1/8 | grep --invert-match inet6 | egrep 'inet ' | awk '{print $2}' | cut --delimiter '/' -f1))
            for index in "${!ip_addrs_array[@]}"
            do
                echo $((index+1))")" "${ip_addrs_array[$index]}"
            done
            echo -ne "${ORANGE}[ QUESTION ]${NOFORMAT} Выберите номер ip-адреса от 1 до ${#ip_addrs_array[*]}: "
            read user_input
            echo ${ip_addrs_array[$user_input-1]}
            ip=$(echo ${ip_addrs_array[$user_input-1]})
            #sed --in-place 's|XXX.XXX.XXX.0|'${ip}'|' /usr/share/rtu5_configurator/.preconf/system-1.zone.conf
        ;;		
    esac

    export IPV4_RTU=$ip
fi
}

function set_configs_api() {
echo -e "${YELLOW}
 ───────────────────────────────────────── Пункт 6 ───────────────────────────────────────────                   
│${B_GREEN}                       Настройка компонентов подсистемы коммутации                           ${YELLOW}│
 ─────────────────────────────────────────────────────────────────────────────────────────────${NOFORMAT}"

# настройка файла phoenix.conf
echo -e ${GREEN}[ INFO ]${NOFORMAT} Изменен адрес в файле /etc/mvts3g/phoenix.conf
sed --in-place 's|management primary=XXX.XXX.XXX.XXX:9000 backup=YYY.YYY.YYY.YYY:9000|management primary=127.0.0.1:9000|' /etc/mvts3g/phoenix.conf

# настройка файла system-1.zone.conf
echo -e ${GREEN}[ INFO ]${NOFORMAT} Изменен адрес в файле /etc/mvts3g/system-1.zone.conf
sed --in-place 's|XXX.XXX.XXX.0/24|'${ip}/32'|' /etc/mvts3g/system-1.zone.conf

# объявление паролей для конфигурации
secret_signaling=$(pwgen -1)
access_db_password=$(cat /etc/mvts3g/access-db.conf | grep passwd | cut --delimiter '=' -f2)
access_logger_db_password=$(cat /etc/mvts3g/access-logger-db.conf | grep passwd | cut --delimiter '=' -f2)

echo -e ${GREEN}[ INFO ]${NOFORMAT} Сгенерирован новый secret, вот он: ${TURQUOISE} [ ${secret_signaling} ] ${NOFORMAT}
echo -e ${GREEN}[ INFO ]${NOFORMAT} Изменены пароли в файле /etc/mvts3g/system-1.scripting.conf

# Обновить пароли в этих файлах для rtu-user
sed --in-place '1,21s|.*dbms_pswd_master.*|                        dbms_pswd_master        "'${access_db_password}'";|g'  /etc/mvts3g/system-1.scripting.conf
sed --in-place '1,21s|.*dbms_pswd_slave.*|                        dbms_pswd_slave         "'${access_db_password}'";|g'  /etc/mvts3g/system-1.scripting.conf

# Обновить пароли в этих файлах для lrtu-user
sed --in-place '24,$s|.*dbms_pswd_master.*|                        dbms_pswd_master        "'${access_logger_db_password}'";|g'  /etc/mvts3g/system-1.scripting.conf
sed --in-place '24,$s|.*dbms_pswd_slave.*|                        dbms_pswd_slave         "'${access_logger_db_password}'";|g'  /etc/mvts3g/system-1.scripting.conf

# запись секрета в файл signaling.conf
echo -e ${GREEN}[ INFO ]${NOFORMAT} Изменен пароль в файле /etc/mvts3g/system-1.signaling.conf 
sed --in-place 's|.*secret.*|                        secret "'${secret_signaling}'";|g' /etc/mvts3g/system-1.signaling.conf 

# смена адреса в файле aps-conf
echo -e ${GREEN}[ INFO ]${NOFORMAT} Изменен адрес в файле /etc/rtu-cl-aps/aps.conf
sed --in-place 's|127.0.0.1|'${IPV4_RTU}'|' /etc/rtu-cl-aps/aps.conf

echo ""

# создаем конфигурационный файл для запуска API-запросов на РТУ МТТ (8445)
echo -e "🚀  Выполлняются API-запросы на РТУ МТТ для заполнения базовых значений, а именно:
${BLUE}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────${NOFORMAT}
1) Добавление модуля sipproxy-MOA-1 
2) Указание зоны в соотвествии с файлом system-1.zone.conf
3) Создание группы балансировки
3) Указание secret на вкладке «Модули балансировки SIP-Глобальная конфигурация»
4) Включение функции «SPTopologyHiding» на вкладке «Модули балансировки SIP-Функции»
5) Указание принимающих сокетов «127.0.0.1:5060 TCP», «<IP зоны voip>:5060 UDP», «<IP зоны voip>:5060 TCP»
6) Включение «Да» на вкладке «Модули балансировки SIP-Замена полей в вызовах» в первых двух необходимых колонках»
${BLUE}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────${NOFORMAT}
"
# выполнение api-запросов
func_mtt_api_processing
source /usr/share/rtu5_installator/vars_installator.sh

sed --in-place 's|0.0.0.0|'${IPV4_RTU}'|g' /etc/mvts3g/mtt_api_config.xml
sed --in-place 's|0.0.0.0:5060|'${IPV4_RTU}':5060|g' /etc/mvts3g/mtt_api_config.xml
sed --in-place 's|secret-hash-mtt|'${secret_signaling}'|g' /etc/mvts3g/mtt_api_config.xml
sed --in-place 's|0.0.0.0:5059|'${IPV4_RTU}':5059|g' /etc/mvts3g/mtt_api_config.xml

# выполняем api-запросы
php /etc/mvts3g/mtt_api_config.xml
}

# Основной блок вызова функций
if [[ $# == 0 ]];
then
	usage
	exit 1;
fi

while [ -n "$*" ]
do
	case "$1" in
        -D)
            check_dns
            check_repos
            install_dependencies
        ;;
		-A) 
			set_log_dir
			configure_network > >(tee -a "${log_file_dir}/installation_log.txt")
			setup_iptables > >(tee -a "${log_file_dir}/installation_log.txt")
            set_configs_api > >(tee -a "${log_file_dir}/installation_log.txt")
    	;;
		-T)
			check_dmidecode
			create_license_archive
		;;
		*) 	
			usage
		;;
	esac
shift
done

exit 0

