#!/usr/bin/env bash
# =============================================================================
# script-00-site-bootstrap.sh — PHASE 0 (COMPLETE) — Iran Trade & Transport ERP
# Odoo 19.0 | File-First | Idempotent | Test-First | Gate-Enforced
#
# پوشش کامل چک‌لیست فاز ۰ نقشهٔ راه MASTER:
#   0.1 پیش‌نیازها | 0.2 سورس/venv | 0.3 addons سفارشی | 0.4 odoo.conf
#   0.5 DB خام بدون دمو | 0.6 fa_IR/Tehran/IR/IRR | 0.7 ADR تقویم جلالی
#   0.8 healthcheck HTTP | 0.9 Git + .gitignore + commit
#   0.10 backup(pg_dump+filestore) + RESTORE TEST واقعی
#   0.11 ماتریس نسخه‌ها | 0.12 DB دوم UAT | 0.13 secrets.env.example
#   0.14 BACKLOG.md (ممنوعه‌ها + قوانین طلایی)
#   + Gate 0 با خروجی سبز/قرمز و exit code (Q08)
#
# پیش‌نیاز: bash script-00-odoo-bootstrap.sh (سورس Odoo 19 + venv + PostgreSQL)
#
# استفاده:
#   chmod +x script-00-site-bootstrap.sh
#   bash script-00-site-bootstrap.sh
# بازتولید DB از صفر:
#   FORCE_DB_RECREATE=1 bash script-00-site-bootstrap.sh
# رد کردن آزمون بازیابی (توصیه نمی‌شود — Gate 0 قرمز می‌شود):
#   SKIP_RESTORE_TEST=1 bash script-00-site-bootstrap.sh
# =============================================================================
set -euo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PYTHONIOENCODING=utf-8

# ───────────────────────────── CONFIG ────────────────────────────────────────
ODOO_DIR="${ODOO_DIR:-${HOME}/odoo}"
VENV_DIR="${VENV_DIR:-${ODOO_DIR}/.venv}"
CONF_DIR="${CONF_DIR:-${HOME}/.config/odoo}"
CONF_FILE="${CONF_FILE:-${CONF_DIR}/odoo.conf}"
CONF_FILE_UAT="${CONF_FILE_UAT:-${CONF_DIR}/odoo-uat.conf}"
DATA_DIR="${DATA_DIR:-${HOME}/.local/share/odoo}"
CUSTOM_ADDONS="${CUSTOM_ADDONS:-${HOME}/odoo-custom-addons}"
BACKUP_DIR="${BACKUP_DIR:-${HOME}/odoo-backups}"
LOG_FILE="${LOG_FILE:-/tmp/odoo19-site-bootstrap.log}"
PID_FILE="${PID_FILE:-/tmp/odoo19-site-bootstrap.pid}"
INIT_LOG="${INIT_LOG:-/tmp/odoo19-init.log}"

DB_NAME="${DB_NAME:-odoo19_dev}"
DB_NAME_UAT="${DB_NAME_UAT:-odoo19_uat}"
DB_NAME_RESTORE="${DB_NAME_RESTORE:-odoo19_restoretest}"

HTTP_INTERFACE="${HTTP_INTERFACE:-0.0.0.0}"
HTTP_PORT="${HTTP_PORT:-8069}"
GEVENT_PORT="${GEVENT_PORT:-8072}"
HTTP_PORT_UAT="${HTTP_PORT_UAT:-8169}"
GEVENT_PORT_UAT="${GEVENT_PORT_UAT:-8172}"

DB_USER="${DB_USER:-$(whoami)}"
DB_HOST="${DB_HOST:-False}"
DB_PORT="${DB_PORT:-False}"
DB_PASSWORD="${DB_PASSWORD:-False}"

LOAD_LANGUAGE="${LOAD_LANGUAGE:-fa_IR}"
TIME_ZONE="${TIME_ZONE:-Asia/Tehran}"
COUNTRY_CODE="${COUNTRY_CODE:-IR}"
CURRENCY_CODE="${CURRENCY_CODE:-IRR}"
WITHOUT_DEMO="${WITHOUT_DEMO:-all}"
WORKERS="${WORKERS:-0}"
MAX_CRON_THREADS="${MAX_CRON_THREADS:-1}"
LIST_DB="${LIST_DB:-True}"
PROXY_MODE="${PROXY_MODE:-False}"

ADMIN_PASSWORD="as12"
MASTER_PASSWD="as12"

FORCE_DB_RECREATE="${FORCE_DB_RECREATE:-0}"
START_DAEMON="${START_DAEMON:-1}"
BUILD_UAT="${BUILD_UAT:-1}"
SKIP_RESTORE_TEST="${SKIP_RESTORE_TEST:-0}"
KEEP_RESTORE_DB="${KEEP_RESTORE_DB:-0}"
DEMO_PARTNER_LIMIT="${DEMO_PARTNER_LIMIT:-12}"
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!!]${NC} $*"; }
info() { echo -e "${BLUE}[..]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${YELLOW}======== $* ========${NC}"; }

GATE_IDS=(); GATE_TXT=(); GATE_ST=(); GATE_MSG=()
gate() { GATE_IDS+=("$1"); GATE_TXT+=("$2"); GATE_ST+=("$3"); GATE_MSG+=("${4:-}"); }

trap 'ec=$?; [[ $ec -ne 0 ]] && { echo -e "\n${RED}[FATAL]${NC} exit=$ec"; [[ -f "${INIT_LOG}" ]] && tail -n 60 "${INIT_LOG}"; }' EXIT

if [[ "$(id -u)" -eq 0 ]]; then
  err "با user عادی اجرا کنید (نه root)."
fi

write_utf8() {
  local target="$1" tmp
  tmp="$(mktemp)"; cat >"$tmp"
  mkdir -p "$(dirname "$target")"
  mv -f "$tmp" "$target"
}

port_in_use() { ss -lntp 2>/dev/null | grep -q ":${1} " && return 0 || return 1; }
db_exists()   { psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${1}'" 2>/dev/null | grep -q 1; }
q()           { psql -d "$1" -Atqc "$2" 2>/dev/null || echo ""; }
have()        { command -v "$1" >/dev/null 2>&1; }

odoo_init_db() {  # $1=conf $2=db
  local conf="$1" db="$2"
  info "init raw DB ${db} (base, without_demo=${WITHOUT_DEMO}, lang=${LOAD_LANGUAGE})"
  if ! python "${ODOO_DIR}/odoo-bin" -c "${conf}" -d "${db}" \
        -i base --without-demo="${WITHOUT_DEMO}" \
        --load-language="${LOAD_LANGUAGE}" --stop-after-init \
        >"${INIT_LOG}" 2>&1; then
    tail -n 80 "${INIT_LOG}"; err "init DB failed: ${db}"
  fi
  log "DB initialized: ${db}"
}

odoo_apply_locale() {  # $1=conf $2=db
  local conf="$1" db="$2"
  export ADMIN_PASSWORD LOAD_LANGUAGE TIME_ZONE COUNTRY_CODE CURRENCY_CODE
  if ! python "${ODOO_DIR}/odoo-bin" shell -c "${conf}" -d "${db}" --stop-after-init \
        <"${OPS_DIR}/bootstrap/locale_setup.py" >>"${INIT_LOG}" 2>&1; then
    tail -n 60 "${INIT_LOG}"; err "locale setup failed on ${db}"
  fi
  log "locale/admin applied on ${db}"
}

# =============================================================================
step "0) preflight — پیش‌نیازها و ابزارها (0.1/0.2/0.3)"
# =============================================================================
[[ -d "${ODOO_DIR}" ]]            || err "ODOO_DIR not found: ${ODOO_DIR} (اول script-00-odoo-bootstrap.sh)"
[[ -f "${ODOO_DIR}/odoo-bin" ]]   || err "odoo-bin missing"
[[ -d "${VENV_DIR}" ]]            || err "venv missing: ${VENV_DIR}"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv python missing"

MISSING=()
for t in psql ss git curl tar pg_dump pg_restore createdb dropdb; do
  have "$t" || MISSING+=("$t")
done
[[ ${#MISSING[@]} -eq 0 ]] || err "ابزارهای لازم غایب: ${MISSING[*]}"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

mkdir -p "${CONF_DIR}" "${DATA_DIR}" "${CUSTOM_ADDONS}" "${BACKUP_DIR}"
mkdir -p "${DATA_DIR}/sessions" "${DATA_DIR}/addons" "${DATA_DIR}/filestore"

PDF_ENGINE="MISSING"
have wkhtmltopdf && PDF_ENGINE="$(wkhtmltopdf --version 2>/dev/null | head -n1 || true)"
RTLCSS_V="MISSING"; have rtlcss && RTLCSS_V="$(rtlcss --version 2>/dev/null | head -n1 || true)"
NODE_V="MISSING";   have node   && NODE_V="$(node --version 2>/dev/null || true)"
PY_V="$(python --version 2>&1)"
PG_V="$(psql --version 2>&1 | head -n1 || true)"
ODOO_V="$("${ODOO_DIR}/odoo-bin" --version 2>/dev/null | head -n1 || echo 'unknown')"
OS_V="$( (source /etc/os-release 2>/dev/null && echo "${PRETTY_NAME}") || uname -a)"
KERNEL_V="$(uname -r)"
GIT_ODOO_REV="$(git -C "${ODOO_DIR}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"

echo "----- versions -----"
echo "OS         : ${OS_V} (kernel ${KERNEL_V})"
echo "Python     : ${PY_V}"
echo "PostgreSQL : ${PG_V}"
echo "Node       : ${NODE_V}"
echo "rtlcss     : ${RTLCSS_V}"
echo "wkhtmltopdf: ${PDF_ENGINE}"
echo "Odoo       : ${ODOO_V} (rev ${GIT_ODOO_REV})"
echo "ADMIN_PASSWORD=${ADMIN_PASSWORD}"
echo "MASTER_PASSWD=${MASTER_PASSWD}"
echo "--------------------"

if [[ "${PDF_ENGINE}" == "MISSING" ]]; then
  gate "G0-01" "موتور PDF (wkhtmltopdf) نصب است [پیش‌نیاز فاز ۹]" "FAIL" "wkhtmltopdf یافت نشد"
else
  gate "G0-01" "موتور PDF (wkhtmltopdf) نصب است" "PASS" "${PDF_ENGINE}"
fi
if [[ "${RTLCSS_V}" == "MISSING" || "${NODE_V}" == "MISSING" ]]; then
  gate "G0-02" "Node + rtlcss برای دارایی‌های RTL" "FAIL" "node=${NODE_V} rtlcss=${RTLCSS_V}"
else
  gate "G0-02" "Node + rtlcss برای دارایی‌های RTL" "PASS" "node=${NODE_V} rtlcss=${RTLCSS_V}"
fi

# =============================================================================
step "1) مخزن Git، اسناد حاکمیتی و اسکریپت‌های ops (0.3/0.7/0.9/0.11/0.13/0.14)"
# =============================================================================
OPS_DIR="${CUSTOM_ADDONS}/ops"
DOC_DIR="${CUSTOM_ADDONS}/docs"
mkdir -p "${OPS_DIR}/bootstrap" "${DOC_DIR}"

# --- .gitignore -------------------------------------------------------------
write_utf8 "${CUSTOM_ADDONS}/.gitignore" <<'EOF'
# ---- Python
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/
# ---- Odoo runtime / data (هرگز داخل مخزن)
*.log
*.pid
*.sql
*.dump
*.zip
filestore/
sessions/
data_dir/
# ---- Secrets (Q12 / NFR-004)
secrets.env
*.secret
*.pem
*.key
.env
# ---- Backups
backups/
*.tar.gz
# ---- Editors / OS
.idea/
.vscode/
.DS_Store
*.swp
EOF

# --- secrets.env.example (0.13) --------------------------------------------
write_utf8 "${CUSTOM_ADDONS}/secrets.env.example" <<'EOF'
# =============================================================================
# secrets.env.example — الگو (بدون مقدار واقعی). کپی کنید به secrets.env
# secrets.env در .gitignore است و هرگز commit نمی‌شود (Q12 / NFR-004).
# =============================================================================
ODOO_MASTER_PASSWD=
ODOO_ADMIN_PASSWORD=
PG_PASSWORD=

# --- SMS gateway (فاز ۲ — itr_notify) : مقدار واقعی فقط روی سرور تولید
ITR_SMS_ADAPTER_KEY=
ITR_SMS_API_KEY=
ITR_SMS_API_SECRET=
ITR_SMS_SENDER_NUMBER=

# --- External systems (فاز ۱۱ — itr_integration)
ITR_SEPIDAR_BASE_URL=
ITR_SEPIDAR_API_KEY=
EOF

# --- VERSION_MATRIX.md (0.11) ----------------------------------------------
write_utf8 "${DOC_DIR}/VERSION_MATRIX.md" <<EOF
# ماتریس نسخه‌ها (Phase 0 — بند 0.11)

تاریخ ثبت: $(date -Is)
میزبان: $(hostname)

| مؤلفه | نسخه |
|---|---|
| OS | ${OS_V} |
| Kernel | ${KERNEL_V} |
| Python | ${PY_V} |
| PostgreSQL | ${PG_V} |
| Node.js | ${NODE_V} |
| rtlcss | ${RTLCSS_V} |
| PDF engine | ${PDF_ENGINE} |
| Odoo | ${ODOO_V} (rev ${GIT_ODOO_REV}) |

## مسیرها
- ODOO_DIR: ${ODOO_DIR}
- VENV_DIR: ${VENV_DIR}
- CONF (dev): ${CONF_FILE}
- CONF (uat): ${CONF_FILE_UAT}
- DATA_DIR: ${DATA_DIR}
- CUSTOM_ADDONS: ${CUSTOM_ADDONS}
- BACKUP_DIR: ${BACKUP_DIR}

## پایگاه‌داده‌ها
- DEV: ${DB_NAME} (http ${HTTP_PORT})
- UAT: ${DB_NAME_UAT} (http ${HTTP_PORT_UAT})
EOF

# --- ARCHITECTURE_DECISIONS.md (0.7 + NFR-013) ------------------------------
if [[ ! -f "${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md" ]]; then
write_utf8 "${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md" <<'EOF'
# ARCHITECTURE DECISIONS (ADR) — Iran Trade & Transport ERP / Odoo 19

هر تصمیم قفل‌شده اینجا ثبت می‌شود (NFR-013 / Q11). تغییر بعدی فقط با Migration رسمی.

## ADR-000 — ترتیب قفل‌شدهٔ نصب ماژول‌ها (Q02)
itr_base → itr_notify → itr_core → itr_transport → itr_reports → itr_integration
یک‌طرفه، بدون حلقه. تاریخ: PHASE-0.

## ADR-001 — تقویم جلالی (بند 0.7)
تصمیم: ذخیره‌سازی داخلی همیشه میلادی/UTC؛ جلالی فقط لایهٔ نمایش/ورودی.
پیاده‌سازی تبدیل در یک ماژول واحد itr_base/utils/jalali.py (تابع خالص، بدون
وابستگی به ماژول Community ناپایدار)، با تست رفت‌وبرگشت روی ≥۵۰ تاریخ مرزی
(نوروز، ۲۹/۳۰ اسفند، سال کبیسه). قانون: تنها یک موتور تقویم در کل مخزن (G18).
وجود هر الگوریتم دوم = Gate قرمز. وضعیت: قفل‌شده در PHASE-0، پیاده‌سازی در PHASE-1.

## ADR-002 — رمز عبور ثابت محیط توسعه (انحراف آگاهانه از بند 0.4)
تصمیم کارفرما: در محیط توسعه، admin_passwd و رمز کاربر admin برابر as12.
پذیرش ریسک: فقط DEV/UAT محلی. در فاز ۱۳ (Go-Live) این مقدار اجباراً با متغیر
محیطی امن جایگزین می‌شود و هرگز در Git قرار نمی‌گیرد (بند 13.5 / Q12).

## ADR-003 — bind روی 0.0.0.0 (انحراف آگاهانه از بند 0.4)
تصمیم: برای دسترسی LAN تیم توسعه، http_interface=0.0.0.0. کنترل جبرانی:
db_filter محدود به یک پایگاه‌داده + فایروال شبکهٔ داخلی. در تولید:
proxy_mode=True پشت reverse-proxy و بستن پورت مستقیم.

## ADR-004 — provisioning محیطی با اسکریپت فایل‌محور (Q01)
تنظیم locale/tz/country/currency و رمز admin دادهٔ کسب‌وکاری نیست؛ از فایل
نسخه‌کنترل‌شدهٔ ops/bootstrap/locale_setup.py به‌صورت غیرتعاملی اجرا می‌شود.
هیچ دادهٔ کسب‌وکاری (نقش، کاربر، پرونده، رویداد اعلان) با shell ساخته نمی‌شود؛
همه از فاز ۱ به بعد فقط داخل ماژول نصب‌شونده.
EOF
fi

# --- BACKLOG.md (0.14) ------------------------------------------------------
write_utf8 "${CUSTOM_ADDONS}/BACKLOG.md" <<'EOF'
# BACKLOG رسمی — محدودهٔ خارج از پروژه (بخش ۱۶ سند نیازمندی)

## ممنوعه‌های دائمی (در هیچ فازی ساخته نمی‌شوند)
- ✗ واتساپ (حذف کامل و دائمی)
- ✗ چت سازمانی مستقل (فقط Chatter استاندارد Odoo)
- ✗ نقشهٔ تعاملی زندهٔ حمل
- ✗ فرم‌ساز / گزارش‌ساز / داشبوردساز عمومی
- ✗ BI بیرونی مستقیم
- ✗ شبیه‌سازی داخلی سپیدار
- ✗ ماژول CRM جانبی (BR-051 / X16)
- ✗ اتوماسیون اداری کامل، رتبه‌بندی خودکار کارکنان، تقویم سازمانی عمومی، تم‌ساز
- ✗ هوش مصنوعی / OCR / بایگانی هوشمند
- ✗ اختراع نام تازه برای وضعیت‌های قفل‌شدهٔ حمل (G10)
- ✗ موتور دوم برای تقویم / SLA / سود / KPI / Task (G18)

## سه قانون طلایی توسعهٔ آینده
1. T1 — هیچ قابلیت به‌تعویق‌افتاده‌ای حق ندارد راه توسعهٔ آینده را ببندد.
2. T2 — هر ارتباط با سیستم بیرونی فقط از مسیر آداپتور/سرویس.
3. T3 — هیچ فیلد یا رابطه‌ای نباید طوری قفل شود که رشد آینده را محدود کند.

## قوانین حاکم بر همهٔ فازها (خلاصه)
- Q01 File-First (ممنوعیت shell برای دادهٔ تولیدی)
- Q03 Administrator بدون هیچ نقش کسب‌وکاری
- Q04 هر مجوز = یک تست مثبت + یک تست منفی
- Q08 بدون Gate سبز، فاز بعدی آغاز نمی‌شود
EOF

# --- README.md --------------------------------------------------------------
write_utf8 "${CUSTOM_ADDONS}/README.md" <<EOF
# Iran Trade & Transport ERP — Custom Addons (Odoo 19)

ترتیب قفل‌شدهٔ نصب (Q02):
itr_base → itr_notify → itr_core → itr_transport → itr_reports → itr_integration

- اسناد حاکمیتی: ARCHITECTURE_DECISIONS.md، BACKLOG.md، docs/VERSION_MATRIX.md
- عملیات: ops/backup.sh، ops/restore.sh، ops/bootstrap/locale_setup.py
- هیچ رمز/دادهٔ واقعی در این مخزن نیست (Q12). الگو: secrets.env.example

محیط‌ها: DEV=${DB_NAME} (پورت ${HTTP_PORT}) | UAT=${DB_NAME_UAT} (پورت ${HTTP_PORT_UAT})
EOF

# --- ops/bootstrap/locale_setup.py (File-First — ADR-004) -------------------
write_utf8 "${OPS_DIR}/bootstrap/locale_setup.py" <<'PY'
# -*- coding: utf-8 -*-
# ops/bootstrap/locale_setup.py — PHASE 0 environment provisioning ONLY.
# فقط locale/tz/country/currency/رمز admin. هیچ دادهٔ کسب‌وکاری اینجا ساخته نمی‌شود (ADR-004).
import os

admin_passwd = os.environ.get("ADMIN_PASSWORD", "as12")
lang_code = os.environ.get("LOAD_LANGUAGE", "fa_IR")
tz_name = os.environ.get("TIME_ZONE", "Asia/Tehran")
country_code = os.environ.get("COUNTRY_CODE", "IR")
currency_code = os.environ.get("CURRENCY_CODE", "IRR")

# 1) زبان فارسی فعال باشد
Lang = env["res.lang"].with_context(active_test=False)
lang_rec = Lang.search([("code", "=", lang_code)], limit=1)
if lang_rec and not lang_rec.active:
    lang_rec.active = True
    print("[..] language activated: %s" % lang_code)

# 2) کاربر admin: رمز + زبان + منطقهٔ زمانی (idempotent)
admin = env.ref("base.user_admin")
vals_admin = {"password": admin_passwd}
if admin.lang != lang_code:
    vals_admin["lang"] = lang_code
if admin.tz != tz_name:
    vals_admin["tz"] = tz_name
admin.sudo().write(vals_admin)

# 3) شرکت: کشور ایران + ارز پایه IRR
# در Odoo 19 فیلد country_id روی res.company از نوع related به partner است
# (non-stored)؛ بنابراین کشور را روی partner شرکت می‌نویسیم.
company = env["res.company"].sudo().search([], limit=1)
partner = company.partner_id.sudo()

country = env["res.country"].sudo().search([("code", "=", country_code)], limit=1)
if not country:
    try:
        country = env.ref("base.ir")
    except Exception:
        country = env["res.country"].browse()
if country and partner.country_id.id != country.id:
    partner.write({"country_id": country.id})
    print("[..] company partner country set: %s" % country_code)

currency = env["res.currency"].with_context(active_test=False).sudo().search(
    [("name", "=", currency_code)], limit=1)
if currency:
    if not currency.active:
        currency.write({"active": True})
    if company.currency_id.id != currency.id:
        company.write({"currency_id": currency.id})
        print("[..] company currency set: %s" % currency_code)

# 4) پیش‌فرض زبان/tz برای کاربران جدید
try:
    env["ir.default"].sudo().set("res.partner", "lang", lang_code)
    env["ir.default"].sudo().set("res.partner", "tz", tz_name)
except Exception as exc:  # non-fatal
    print("[!!] ir.default skipped: %s" % exc)

env.cr.commit()
print("[OK] locale_setup done: lang=%s tz=%s country=%s currency=%s"
      % (lang_code, tz_name, country_code, currency_code))
PY

# --- ops/backup.sh (0.10) ---------------------------------------------------
write_utf8 "${OPS_DIR}/backup.sh" <<'EOF'
#!/usr/bin/env bash
# ops/backup.sh <db_name> [backup_dir] — pg_dump (-Fc) + filestore tar + SHA256
set -euo pipefail
DB="${1:?usage: backup.sh <db_name> [backup_dir]}"
OUT="${2:-${HOME}/odoo-backups}"
DATA_DIR="${DATA_DIR:-${HOME}/.local/share/odoo}"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUT}"
DUMP="${OUT}/${DB}-${TS}.dump"
FS_TAR="${OUT}/${DB}-${TS}-filestore.tar.gz"

pg_dump -Fc -d "${DB}" -f "${DUMP}"
if [[ -d "${DATA_DIR}/filestore/${DB}" ]]; then
  tar -czf "${FS_TAR}" -C "${DATA_DIR}/filestore" "${DB}"
else
  tar -czf "${FS_TAR}" --files-from /dev/null
fi
sha256sum "${DUMP}" "${FS_TAR}" > "${OUT}/${DB}-${TS}.sha256"
echo "${DUMP}"
echo "${FS_TAR}"
EOF
chmod +x "${OPS_DIR}/backup.sh"

# --- ops/restore.sh (0.10) --------------------------------------------------
write_utf8 "${OPS_DIR}/restore.sh" <<'EOF'
#!/usr/bin/env bash
# ops/restore.sh <dump_file> <filestore_tar> <target_db>
set -euo pipefail
DUMP="${1:?usage: restore.sh <dump_file> <filestore_tar> <target_db>}"
FS_TAR="${2:?}"
TARGET="${3:?}"
DATA_DIR="${DATA_DIR:-${HOME}/.local/share/odoo}"

if psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${TARGET}'" | grep -q 1; then
  psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${TARGET}' AND pid <> pg_backend_pid();" >/dev/null
  dropdb "${TARGET}"
fi
createdb "${TARGET}"
pg_restore -d "${TARGET}" --no-owner --no-privileges "${DUMP}" >/dev/null 2>&1 || true

rm -rf "${DATA_DIR}/filestore/${TARGET}"
mkdir -p "${DATA_DIR}/filestore"
TMPD="$(mktemp -d)"
tar -xzf "${FS_TAR}" -C "${TMPD}" 2>/dev/null || true
SRC="$(find "${TMPD}" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
if [[ -n "${SRC}" ]]; then mv "${SRC}" "${DATA_DIR}/filestore/${TARGET}"; else mkdir -p "${DATA_DIR}/filestore/${TARGET}"; fi
rm -rf "${TMPD}"

# پاک‌سازی cron/mail در نسخهٔ بازیابی‌شده (جلوگیری از اجرای ناخواسته)
psql -d "${TARGET}" -c "UPDATE ir_cron SET active=false;" >/dev/null 2>&1 || true
echo "[OK] restored into ${TARGET}"
EOF
chmod +x "${OPS_DIR}/restore.sh"

# --- git init + commit (0.9) ------------------------------------------------
if [[ ! -d "${CUSTOM_ADDONS}/.git" ]]; then
  git -C "${CUSTOM_ADDONS}" init -q
  git -C "${CUSTOM_ADDONS}" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
  log "git repo initialized: ${CUSTOM_ADDONS}"
fi
git -C "${CUSTOM_ADDONS}" config user.name  >/dev/null 2>&1 || git -C "${CUSTOM_ADDONS}" config user.name  "itr-bootstrap"
git -C "${CUSTOM_ADDONS}" config user.email >/dev/null 2>&1 || git -C "${CUSTOM_ADDONS}" config user.email "itr-bootstrap@localhost"
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "commit جدیدی لازم نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-0: env bootstrap, ADR, backlog, ops scripts, version matrix"
  log "git commit ثبت شد"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-0 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-0 || true
fi
GIT_HEAD="$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
[[ "${GIT_HEAD}" != "n/a" ]] \
  && gate "G0-08" "مخزن Git + .gitignore + commit اولیه (0.9)" "PASS" "HEAD=${GIT_HEAD} tag=phase-0" \
  || gate "G0-08" "مخزن Git + .gitignore + commit اولیه (0.9)" "FAIL" "commit ساخته نشد"

# --- اسکن رمز در فایل‌های ردیابی‌شده (Gate 0 / Q12) -------------------------
SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z | xargs -0 -r grep -nIE '(as12|admin_passwd[[:space:]]*=[[:space:]]*[^[:space:]]|api[_-]?key[[:space:]]*=[[:space:]]*[^[:space:]]|password[[:space:]]*=[[:space:]]*[^[:space:]])' 2>/dev/null | grep -v 'secrets.env.example' | grep -v 'ARCHITECTURE_DECISIONS.md' || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G0-09" "هیچ رمزی در فایل‌های نسخه‌کنترل‌شده نیست (Q12)" "PASS" "clean"
else
  gate "G0-09" "هیچ رمزی در فایل‌های نسخه‌کنترل‌شده نیست (Q12)" "FAIL" "$(echo "${SECRET_HITS}" | head -n3 | tr '\n' ' ')"
fi

# =============================================================================
step "2) نوشتن odoo.conf برای DEV و UAT (0.4/0.12)"
# =============================================================================
ADDONS_PATH="${ODOO_DIR}/addons,${CUSTOM_ADDONS}"
if [[ -d "${ODOO_DIR}/odoo/addons" ]]; then
  ADDONS_PATH="${ODOO_DIR}/odoo/addons,${ODOO_DIR}/addons,${CUSTOM_ADDONS}"
fi

gen_conf() {  # $1=target $2=db $3=http_port $4=gevent_port
write_utf8 "$1" <<EOF
[options]
admin_passwd = ${MASTER_PASSWD}
http_interface = ${HTTP_INTERFACE}
http_port = ${3}
gevent_port = ${4}
db_host = ${DB_HOST}
db_port = ${DB_PORT}
db_user = ${DB_USER}
db_password = ${DB_PASSWORD}
db_name = ${2}
list_db = ${LIST_DB}
db_filter = ^${2}$
addons_path = ${ADDONS_PATH}
data_dir = ${DATA_DIR}
without_demo = ${WITHOUT_DEMO}
workers = ${WORKERS}
max_cron_threads = ${MAX_CRON_THREADS}
proxy_mode = ${PROXY_MODE}
log_level = info
syslog = False
EOF
chmod 600 "$1"
}

gen_conf "${CONF_FILE}"     "${DB_NAME}"     "${HTTP_PORT}"     "${GEVENT_PORT}"
gen_conf "${CONF_FILE_UAT}" "${DB_NAME_UAT}" "${HTTP_PORT_UAT}" "${GEVENT_PORT_UAT}"
log "conf(dev): ${CONF_FILE}"
log "conf(uat): ${CONF_FILE_UAT}"

# grep -F: $ در مقدار db_filter حرفی است، نه anchor انتهای خط
if grep -qF "db_filter = ^${DB_NAME}$" "${CONF_FILE}" && [[ "$(stat -c '%a' "${CONF_FILE}")" == "600" ]]; then
  gate "G0-03" "conf نوشته شد؛ db_filter محدود و مجوز 600 (0.4)" "PASS" "db_filter=^${DB_NAME}$"
else
  gate "G0-03" "conf نوشته شد؛ db_filter محدود و مجوز 600 (0.4)" "FAIL" "بررسی db_filter/permission perm=$(stat -c '%a' "${CONF_FILE}" 2>/dev/null || echo '?')"
fi

# =============================================================================
step "3) اتصال PostgreSQL"
# =============================================================================
psql -d postgres -Atqc "SELECT 'pg_ok:' || current_user" || err "عدم اتصال به PostgreSQL با user=${DB_USER}"

# =============================================================================
step "4) پایگاه‌دادهٔ DEV — خام/صفر (0.5) — NO DROP پیش‌فرض"
# =============================================================================
stop_odoo() {
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}" 2>/dev/null)" 2>/dev/null; then
    kill "$(cat "${PID_FILE}")" 2>/dev/null || true; sleep 2
  fi
  pkill -f "odoo-bin.*${CONF_FILE}" 2>/dev/null || true; sleep 1
}

drop_db() {
  psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${1}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
  dropdb "${1}" || err "dropdb failed: ${1}"
  rm -rf "${DATA_DIR}/filestore/${1}"
  log "dropped ${1} (+filestore)"
}

if db_exists "${DB_NAME}"; then
  if [[ "${FORCE_DB_RECREATE}" == "1" ]]; then
    warn "FORCE_DB_RECREATE=1 — توقف odoo و DROP ${DB_NAME}"
    stop_odoo; drop_db "${DB_NAME}"
  else
    warn "DB ${DB_NAME} از قبل موجود است — رد شد (NO DROP). ساخت مجدد: FORCE_DB_RECREATE=1"
  fi
fi
if ! db_exists "${DB_NAME}"; then
  odoo_init_db "${CONF_FILE}" "${DB_NAME}"
  odoo_apply_locale "${CONF_FILE}" "${DB_NAME}"
else
  odoo_apply_locale "${CONF_FILE}" "${DB_NAME}"   # idempotent
fi

# =============================================================================
step "5) پایگاه‌دادهٔ UAT مستقل (0.12)"
# =============================================================================
if [[ "${BUILD_UAT}" != "1" ]]; then
  warn "BUILD_UAT=0 — ساخت UAT رد شد"
  gate "G0-07" "پایگاه‌دادهٔ UAT مستقل و سالم (0.12)" "FAIL" "BUILD_UAT=0"
else
  if db_exists "${DB_NAME_UAT}" && [[ "${FORCE_DB_RECREATE}" == "1" ]]; then
    drop_db "${DB_NAME_UAT}"
  fi
  if ! db_exists "${DB_NAME_UAT}"; then
    odoo_init_db "${CONF_FILE_UAT}" "${DB_NAME_UAT}"
    odoo_apply_locale "${CONF_FILE_UAT}" "${DB_NAME_UAT}"
  else
    warn "UAT DB از قبل موجود است — init رد شد"
    odoo_apply_locale "${CONF_FILE_UAT}" "${DB_NAME_UAT}"   # idempotent locale fix
  fi
  UAT_MODS="$(q "${DB_NAME_UAT}" "SELECT count(*) FROM ir_module_module WHERE state='installed'")"
  UAT_DEMO="$(q "${DB_NAME_UAT}" "SELECT count(*) FROM ir_module_module WHERE demo IS TRUE")"
  if [[ "${UAT_MODS:-0}" -gt 0 && "${UAT_DEMO:-1}" == "0" ]]; then
    gate "G0-07" "پایگاه‌دادهٔ UAT مستقل و بدون دمو (0.12)" "PASS" "modules=${UAT_MODS} demo=0"
  else
    gate "G0-07" "پایگاه‌دادهٔ UAT مستقل و بدون دمو (0.12)" "FAIL" "modules=${UAT_MODS} demo=${UAT_DEMO}"
  fi
fi

# =============================================================================
step "6) راستی‌آزمایی محتوای DEV: بدون دمو + fa_IR + Tehran + IR + IRR"
# =============================================================================
DEMO_FLAG="$(q "${DB_NAME}" "SELECT count(*) FROM ir_module_module WHERE demo IS TRUE")"
PARTNER_CNT="$(q "${DB_NAME}" "SELECT count(*) FROM res_partner")"
USER_CNT="$(q "${DB_NAME}" "SELECT count(*) FROM res_users")"
MOD_CNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_module_module WHERE state='installed'")"
LANG_OK="$(q "${DB_NAME}" "SELECT count(*) FROM res_lang WHERE code='${LOAD_LANGUAGE}' AND active IS TRUE")"
ADMIN_LANG="$(q "${DB_NAME}" "SELECT p.lang FROM res_users u JOIN res_partner p ON p.id=u.partner_id WHERE u.login='admin'")"
ADMIN_TZ="$(q "${DB_NAME}" "SELECT p.tz FROM res_users u JOIN res_partner p ON p.id=u.partner_id WHERE u.login='admin'")"
# country_id روی res.company در Odoo 19 related/non-stored است → از partner بخوان
CO_COUNTRY="$(q "${DB_NAME}" "SELECT co.code FROM res_company c JOIN res_partner p ON p.id=c.partner_id LEFT JOIN res_country co ON co.id=p.country_id ORDER BY c.id LIMIT 1")"
CO_CURR="$(q "${DB_NAME}" "SELECT cur.name FROM res_company c JOIN res_currency cur ON cur.id=c.currency_id ORDER BY c.id LIMIT 1")"

echo "installed_modules=${MOD_CNT} users=${USER_CNT} partners=${PARTNER_CNT} demo_modules=${DEMO_FLAG}"
echo "lang_active=${LANG_OK} admin_lang=${ADMIN_LANG} admin_tz=${ADMIN_TZ} country=${CO_COUNTRY} currency=${CO_CURR}"

if [[ "${DEMO_FLAG:-1}" == "0" && "${PARTNER_CNT:-999}" -le "${DEMO_PARTNER_LIMIT}" ]]; then
  gate "G0-04" "پایگاه‌داده کاملاً فاقد دادهٔ نمایشی (0.5)" "PASS" "demo=0 partners=${PARTNER_CNT}"
else
  gate "G0-04" "پایگاه‌داده کاملاً فاقد دادهٔ نمایشی (0.5)" "FAIL" "demo=${DEMO_FLAG} partners=${PARTNER_CNT} (حد=${DEMO_PARTNER_LIMIT})"
fi
if [[ "${LANG_OK}" == "1" && "${ADMIN_LANG}" == "${LOAD_LANGUAGE}" && "${ADMIN_TZ}" == "${TIME_ZONE}" ]]; then
  gate "G0-05" "زبان fa_IR فعال + admin با fa_IR/Asia-Tehran (0.6)" "PASS" "lang=${ADMIN_LANG} tz=${ADMIN_TZ}"
else
  gate "G0-05" "زبان fa_IR فعال + admin با fa_IR/Asia-Tehran (0.6)" "FAIL" "lang_active=${LANG_OK} admin_lang=${ADMIN_LANG} tz=${ADMIN_TZ}"
fi
if [[ "${CO_COUNTRY}" == "${COUNTRY_CODE}" && "${CO_CURR}" == "${CURRENCY_CODE}" ]]; then
  gate "G0-06" "کشور ایران + ارز پایه IRR روی شرکت (0.6)" "PASS" "country=${CO_COUNTRY} currency=${CO_CURR}"
else
  gate "G0-06" "کشور ایران + ارز پایه IRR روی شرکت (0.6)" "FAIL" "country=${CO_COUNTRY} currency=${CO_CURR}"
fi

# =============================================================================
step "7) پشتیبان‌گیری + آزمون بازیابی واقعی (0.10 — الزام Gate 0)"
# =============================================================================
if [[ "${SKIP_RESTORE_TEST}" == "1" ]]; then
  gate "G0-10" "پشتیبان کامل (pg_dump + filestore)" "FAIL" "SKIP_RESTORE_TEST=1"
  gate "G0-11" "بازیابی واقعی روی پایگاه‌دادهٔ خالی موفق است" "FAIL" "SKIP_RESTORE_TEST=1"
else
  info "backup ..."
  mapfile -t BK < <(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}")
  DUMP_FILE="${BK[0]:-}"; FS_FILE="${BK[1]:-}"
  if [[ -s "${DUMP_FILE}" && -f "${FS_FILE}" ]]; then
    DUMP_SZ="$(stat -c '%s' "${DUMP_FILE}")"
    gate "G0-10" "پشتیبان کامل (pg_dump -Fc + filestore + sha256)" "PASS" "$(basename "${DUMP_FILE}") ${DUMP_SZ}B"
  else
    gate "G0-10" "پشتیبان کامل (pg_dump -Fc + filestore + sha256)" "FAIL" "فایل پشتیبان ساخته نشد"
  fi

  info "restore test → ${DB_NAME_RESTORE}"
  if DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/restore.sh" "${DUMP_FILE}" "${FS_FILE}" "${DB_NAME_RESTORE}" >/dev/null; then
    R_USERS="$(q "${DB_NAME_RESTORE}" "SELECT count(*) FROM res_users")"
    R_MODS="$(q "${DB_NAME_RESTORE}" "SELECT count(*) FROM ir_module_module WHERE state='installed'")"
    if [[ -n "${R_USERS}" && "${R_USERS}" == "${USER_CNT}" && "${R_MODS}" == "${MOD_CNT}" ]]; then
      gate "G0-11" "بازیابی واقعی روی DB خالی موفق و برابر مبدأ" "PASS" "users=${R_USERS}/${USER_CNT} modules=${R_MODS}/${MOD_CNT}"
    else
      gate "G0-11" "بازیابی واقعی روی DB خالی موفق و برابر مبدأ" "FAIL" "users=${R_USERS}/${USER_CNT} modules=${R_MODS}/${MOD_CNT}"
    fi
    if [[ "${KEEP_RESTORE_DB}" != "1" ]]; then
      drop_db "${DB_NAME_RESTORE}" >/dev/null 2>&1 || true
      log "restore-test DB پاک شد"
    fi
  else
    gate "G0-11" "بازیابی واقعی روی DB خالی موفق و برابر مبدأ" "FAIL" "restore.sh خطا داد"
  fi
fi

# =============================================================================
step "8) اجرای Odoo روی ${HTTP_INTERFACE}:${HTTP_PORT} + healthcheck HTTP (0.8)"
# =============================================================================
if [[ "${START_DAEMON}" != "1" ]]; then
  warn "START_DAEMON=0 — start رد شد"
  gate "G0-12" "سرویس بالا و صفحهٔ ورود HTTP 200 (0.8)" "FAIL" "START_DAEMON=0"
  gate "G0-13" "listen روی ${HTTP_INTERFACE}:${HTTP_PORT}" "FAIL" "start نشد"
else
  if port_in_use "${HTTP_PORT}"; then
    warn "port ${HTTP_PORT} از قبل listen است — start رد شد (idempotent)"
  elif [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}" 2>/dev/null)" 2>/dev/null; then
    warn "pidfile زنده است pid=$(cat "${PID_FILE}") — start رد شد"
  else
    rm -f "${PID_FILE}"
    nohup python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
      --http-interface="${HTTP_INTERFACE}" --http-port="${HTTP_PORT}" \
      >"${LOG_FILE}" 2>&1 &
    echo $! >"${PID_FILE}"
    sleep 3
    kill -0 "$(cat "${PID_FILE}")" 2>/dev/null || { tail -n 60 "${LOG_FILE}"; err "odoo start failed"; }
    log "odoo started pid=$(cat "${PID_FILE}") log=${LOG_FILE}"
  fi

  HTTP_CODE="000"
  for _ in $(seq 1 30); do
    HTTP_CODE="$(curl -s -o /tmp/odoo19-login.html -w '%{http_code}' "http://127.0.0.1:${HTTP_PORT}/web/login" || echo 000)"
    [[ "${HTTP_CODE}" == "200" ]] && break
    sleep 2
  done
  if [[ "${HTTP_CODE}" == "200" ]]; then
    RTL_HINT="no"
    grep -qiE 'dir="rtl"|direction:[[:space:]]*rtl|lang="fa' /tmp/odoo19-login.html && RTL_HINT="yes"
    gate "G0-12" "سرویس بالا و صفحهٔ ورود HTTP 200 (0.8)" "PASS" "code=200 rtl_hint=${RTL_HINT}"
  else
    gate "G0-12" "سرویس بالا و صفحهٔ ورود HTTP 200 (0.8)" "FAIL" "code=${HTTP_CODE} (tail ${LOG_FILE})"
  fi

  if ss -lntp 2>/dev/null | grep -q ":${HTTP_PORT} "; then
    gate "G0-13" "listen روی پورت ${HTTP_PORT}" "PASS" "$(ss -lntp 2>/dev/null | grep ":${HTTP_PORT} " | head -n1 | tr -s ' ' || true)"
  else
    gate "G0-13" "listen روی پورت ${HTTP_PORT}" "FAIL" "پورت listen نیست"
  fi
fi

# =============================================================================
step "9) اثبات Idempotency (Q09 / NFR-002)"
# =============================================================================
STATE_FILE="${BACKUP_DIR}/.phase0-state"
CUR_SIG="users=${USER_CNT};partners=${PARTNER_CNT};modules=${MOD_CNT}"
if [[ -f "${STATE_FILE}" ]]; then
  PREV_SIG="$(cat "${STATE_FILE}")"
  if [[ "${PREV_SIG}" == "${CUR_SIG}" ]]; then
    gate "G0-14" "اجرای دوباره رکورد تکراری نساخت (Idempotent)" "PASS" "${CUR_SIG}"
  else
    gate "G0-14" "اجرای دوباره رکورد تکراری نساخت (Idempotent)" "FAIL" "prev[${PREV_SIG}] != now[${CUR_SIG}]"
  fi
else
  gate "G0-14" "خط‌مبنای Idempotency ثبت شد (اجرای اول)" "PASS" "${CUR_SIG}"
fi
echo "${CUR_SIG}" > "${STATE_FILE}"

# =============================================================================
step "GATE 0 — گزارش پذیرش فاز ۰"
# =============================================================================
FAILS=0
printf "\n%-8s %-8s %s\n" "ID" "STATUS" "CHECK"
printf -- "---------------------------------------------------------------------------\n"
for i in "${!GATE_IDS[@]}"; do
  st="${GATE_ST[$i]}"
  if [[ "${st}" == "PASS" ]]; then c="${GREEN}"; else c="${RED}"; FAILS=$((FAILS+1)); fi
  printf "%-8s ${c}%-8s${NC} %s\n" "${GATE_IDS[$i]}" "${st}" "${GATE_TXT[$i]}"
  [[ -n "${GATE_MSG[$i]}" ]] && printf "%-8s %-8s   ↳ %s\n" "" "" "${GATE_MSG[$i]}"
done
printf -- "---------------------------------------------------------------------------\n"

IPS="$(hostname -I 2>/dev/null || true)"
cat <<FINAL

URL (local):   http://127.0.0.1:${HTTP_PORT}
URL (bind):    http://${HTTP_INTERFACE}:${HTTP_PORT}
LAN IPs:       ${IPS}
DB (dev):      ${DB_NAME}
DB (uat):      ${DB_NAME_UAT}   (conf: ${CONF_FILE_UAT}, port ${HTTP_PORT_UAT})
Conf:          ${CONF_FILE}
Data dir:      ${DATA_DIR}
Backups:       ${BACKUP_DIR}
Addons repo:   ${CUSTOM_ADDONS} (HEAD=${GIT_HEAD}, tag=phase-0)
Log:           ${LOG_FILE}
PID file:      ${PID_FILE}
Addons path:   ${ADDONS_PATH}

Login:  user: admin   pass: as12
Master password (db manager): as12

توقف:  kill \$(cat ${PID_FILE}) 2>/dev/null || pkill -f 'odoo-bin.*${CONF_FILE}'

اجرای UAT (جداگانه):
  python ${ODOO_DIR}/odoo-bin -c ${CONF_FILE_UAT} -d ${DB_NAME_UAT}

بازتولید کامل از صفر:  FORCE_DB_RECREATE=1 bash script-00-site-bootstrap.sh
FINAL

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 0 = سبز ✅ — مجاز به شروع فاز ۱ (itr_base).${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 0 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۱ آغاز نمی‌شود.${NC}\n"
  exit 1
fi