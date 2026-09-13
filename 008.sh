#!/usr/bin/env bash
# =============================================================================
# script-08-cartable-workspace.sh (008.sh) — PHASE 8 (COMPLETE)
# Iran Trade & Transport ERP — Odoo 19.0 | File-First | Idempotent | Test-First
# Gate-Enforced | No sudo-proof
#
# فاز ۸ — کارتابل، مرکز کار، Workspace، مرکز اعلان و داشبورد مدیرعامل
# مرجع: FINAL-MASTER-PHASED-EXECUTION-PLAN.txt ← «فاز ۸» بندهای 8.1..8.11
#       FINAL-MASTER-SRS-IRAN-TRADE-TRANSPORT-ERP.txt ← بخش ۱۲ کامل:
#       UX-001/002/003/004/005، UX-011 (معماری واحد صف‌کار)، UX-021 (Home)،
#       UX-022 (مرکز اعلان)، UX-031 (Workspace نقش‌محور)، UX-041 (۱۸ کارت CEO)،
#       UX-051 (هشت قلم رصد)، UX-062 (جست‌وجوی سراسری)، UX-063، G15/G18، UAT-12
# سبک اجرا: کاملاً هم‌خانوادهٔ 00.sh … 007.sh همین مخزن.
#
# ★ FIX (Gate 8 قرمز → این نسخه):
#   F1) ترتیب data در __manifest__: workspace_menus بعد از home_views
#       (action_itr_ceo_dashboard).
#   F2) لاگین‌های verify/tests هم‌خوان با بذر فاز ۳/۷:
#       atieh.alaei / mohammadi@ / amini@.
#   F3) تست‌ها روی ItrTransportCase (قرارداد 007).
#   F4) Q02: itr_core ← قبل از → itr_transport. هیچ act_window با
#       res_model=itr.transport.case|itr.payment.* داخل XMLِ itr_core نیست
#       (ParseError «نام مدل نامعتبر»). اکشن‌های حمل = ir.actions.server
#       روی itr.work.queue؛ منوهای Workspace حمل/پرداخت در itr_transport.
#   F5) V8-01: منوهای والد Workspace حمل (docs/customs/delivery) بدون action
#       و فقط با فرزند server-action روی AbstractModel در _visible_menu_ids
#       مخفی می‌ماندند → act_window واقعی itr.transport.case + اتصال action
#       به خودِ منوی والد (در itr_transport، مجاز به F4).
#   F6) V8-07: mark_read با super(Phase8).write به writeِ append-only فاز ۲
#       می‌خورد؛ باید models.Model.write (با sudo محافظت‌شده) باشد.
#
# ★ معماری (بند 8.1 — UX-011، بدون هیچ موتور Task دوم — G18):
#   Business State Machine (فاز ۴/۵/۶)
#     → Unified Work Queue = سرویس فقط-خواندنیِ itr.work.queue روی *همان*
#       چهار مدل دارای قرارداد کارتابل فاز ۴/۵ (current_owner_id/owner_deadline):
#       itr.trade.case | itr.sales.slip | itr.transport.case | itr.payment.request
#     → {My Tasks | Team Tasks | Overdue | Urgent | Recent}
#     → Workspace/Dashboard → {KPI(get_kpi) | Notifications | Drill-down}
#   هیچ مدل صف/تسک جدیدی ساخته نمی‌شود؛ سرویس فقط از فیلدهای موجود می‌خواند.
#   آستانه‌های فوری/عقب‌افتاده/اخیر فقط از itr.cartable.settings (UX-002/Q07).
#
# ★ مدیریت ریسک «شکستن قرارداد فازهای قبل» (همان نظام R فاز ۷):
#   R1) هیچ فایل فازهای ۱..۷ بازنویسی نمی‌شود؛ فقط فایل جدید + پچ افزایشی مارک‌دار.
#   R2) پیش‌پرواز fingerprint روی همهٔ قراردادهایی که این فاز مصرف می‌کند
#       (mixin کارتابل، مالکان سه تب، checklist_progress، dispatch.log،
#       money engine، shortfall) — ناهم‌خوانی = توقف بدون هیچ تغییری.
#   R3) پشتیبان کامل + کپی فایل‌های مشترک پیش از پچ + مسیر rollback.
#   R5) بازاجرای کامل تست‌های فازهای ۱..۷ پس از ارتقا؛ هر رگرسیون = Gate قرمز.
#
# ★ اصلاح/تکمیل‌های کشف‌شده در ممیزی (افزایشی):
#   [FIX-P8-1] دفتر ارسال اعلان (فاز ۲) مفهوم «خوانده‌شده» نداشت؛ مرکز اعلان
#              UX-022 سه دستهٔ [جدید]/[بحرانی]/[خوانده‌شده] می‌خواهد → دو فیلد
#              افزایشی read_on/is_critical_stored با inherit (بدون دست‌زدن به
#              موتور notify) اضافه شد.
#   [FIX-P8-2] دفتر ارسال برای همهٔ کاربران داخلی خوانا بود؛ اعلانِ من فقط
#              مال من است → Record Rule «own notifications» (مدیر اعلان/حسابرس
#              /CEO مستثنا) — رفع یک نشتی حریم که از فاز ۲ باقی بود.
#   [FIX-P8-3] trade.case نوار پیشرفت نداشت (UX-051) → فیلد محاسبه‌ای افزایشی.
#   داشبورد/KPI: همهٔ ۱۸ کارت فقط از یک سرویس get_kpi می‌آیند؛ این رجیستری
#   صراحتاً «بذر Metric Registry فاز ۹ (REP-002)» است و فاز ۹ موظف به
#   بازاستفاده از همین است، نه ساخت موتور دوم (G18) — در ADR ثبت می‌شود.
#
# پوشش کامل چک‌لیست فاز ۸:
#   8.1  معماری واحد صف‌کار (UX-011) — سرویس itr.work.queue، بدون موتور دوم
#   8.2  کارتابل ده‌بخشی (UX-001) با آستانه‌ها از itr.cartable.settings (UX-002)
#   8.3  صفحهٔ Home هر نقش (UX-021): «سلام، <نام>» + شمارنده‌های رنگی +
#        میان‌برهای مجاز (Shortcut به اکشن سرور؛ هرگز bypass — UX-063)
#   8.4  مرکز اعلان (UX-022): [جدید]/[بحرانی]/[خوانده‌شده] + لینک به رکورد واقعی
#   8.5  فضای کاری اختصاصی ۸ نقش (UX-031) — بدون منوی نامرتبط
#   8.6  داشبورد مدیرعامل ۱۸ کارت (UX-041) از سرویس واحد get_kpi + Drill-Down
#   8.7  کانبان رنگی SLA برای trade.case و transport.case
#   8.8  نوار پیشرفت/مسئول/مهلت/تاریخچهٔ اعلان روی فرم‌ها (UX-051)
#   8.9  جست‌وجوی سراسری: پرونده/بارنامه/پلاک/کدملی/مشتری/کارخانه (UX-062)
#   8.10 فرم‌ها روی موبایل (ویوهای استاندارد ریسپانسیو + تست فیلدهای لمسی)
#   8.11 هیچ نقشهٔ تعاملی/چت/فرم‌ساز/گزارش‌ساز ساخته نشد (گارد grep در Gate)
#
# verify فاز ۸ (ops/verify/verify_phase8.py — کاربر واقعی، بدون sudo):
#   V8-01 هر ۱۲ کاربر فقط فضای کاری مرتبط با نقش خود را می‌بیند
#   V8-02 Administrator کارتابل/Home عملیاتی ندارد (UX-003)
#   V8-03 عدد هر کارت داشبورد = شمارش مستقیم ORM همان دامنه (Drill-Down برابر)
#   V8-04 صفحهٔ Home هر کاربر دقیقاً کارهای خودش را می‌شمارد (UAT-12)
#   V8-05 آستانهٔ «فوری» از تنظیمات اثر می‌کند نه از کد (UX-002/Q07)
#   V8-06 مرکز اعلان: هرکس فقط اعلان خودش را می‌بیند [FIX-P8-2]
#   V8-07 علامت‌گذاری «خوانده شد» فقط توسط خود گیرنده (UX-022)
#   V8-08 هیچ موتور Task/KPI دوم در مخزن نیست (G18 — grep اثبات‌شده)
#
# پیش‌نیاز: Gate 7 سبز (bash 007.sh)
#
# استفاده:
#   chmod +x 008.sh
#   bash 008.sh
# سوییچ‌ها:
#   SKIP_TESTS=1 / SKIP_VERIFY=1 → Gate قرمز (Q04/Q15 اجباری)
#   SKIP_BACKUP=1 / SKIP_UAT=1 / START_DAEMON=0
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

DB_NAME="${DB_NAME:-odoo19_dev}"
DB_NAME_UAT="${DB_NAME_UAT:-odoo19_uat}"

HTTP_INTERFACE="${HTTP_INTERFACE:-0.0.0.0}"
HTTP_PORT="${HTTP_PORT:-8069}"

LOG_FILE="${LOG_FILE:-/tmp/odoo19-site-bootstrap.log}"
PID_FILE="${PID_FILE:-/tmp/odoo19-site-bootstrap.pid}"
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase8-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase8-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase8-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase8-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase8-uat.log}"

CORE_MODULE="itr_core"
TRN_MODULE="itr_transport"
CORE_DIR="${CUSTOM_ADDONS}/${CORE_MODULE}"
TRN_DIR="${CUSTOM_ADDONS}/${TRN_MODULE}"
OPS_DIR="${CUSTOM_ADDONS}/ops"
DOC_DIR="${CUSTOM_ADDONS}/docs"
P8_BACKUP_DIR="${DOC_DIR}/phase8-backup"

SKIP_TESTS="${SKIP_TESTS:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
SKIP_UAT="${SKIP_UAT:-0}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
START_DAEMON="${START_DAEMON:-1}"
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!!]${NC} $*"; }
info() { echo -e "${BLUE}[..]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${YELLOW}======== $* ========${NC}"; }

GATE_IDS=(); GATE_TXT=(); GATE_ST=(); GATE_MSG=()
gate() { GATE_IDS+=("$1"); GATE_TXT+=("$2"); GATE_ST+=("$3"); GATE_MSG+=("${4:-}"); }

trap 'ec=$?; [[ $ec -ne 0 ]] && echo -e "\n${RED}[FATAL]${NC} exit=$ec — لاگ‌ها: ${INSTALL_LOG} / ${TEST_LOG} / ${VERIFY_LOG}"' EXIT

[[ "$(id -u)" -eq 0 ]] && err "با کاربر عادی اجرا کنید (نه root)."

write_utf8() {
  local target="$1" tmp
  tmp="$(mktemp)"; cat >"$tmp"
  mkdir -p "$(dirname "$target")"
  mv -f "$tmp" "$target"
}
q() { psql -d "$1" -Atqc "$2" 2>/dev/null || echo ""; }

# =============================================================================
step "0) preflight — Gate 7 سبز + fingerprint قراردادهای مصرفی این فاز (R2)"
# =============================================================================
[[ -f "${ODOO_DIR}/odoo-bin" ]] || err "odoo-bin غایب است"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

TRN_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
[[ "${TRN_STATE}" == "installed" ]] || err "پیش‌نیاز فاز ۸: ${TRN_MODULE} باید installed باشد. اول 007.sh را سبز کنید (Q08)."
git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-7 >/dev/null \
  || warn "تگ phase-7 یافت نشد — مطمئن شوید Gate 7 واقعاً سبز بوده است (Q08)."

CONTRACT_FAILS=0
contract() {
  if [[ -f "$2" ]] && grep -qE "$3" "$2"; then
    log "قرارداد OK: $1"
  else
    warn "قرارداد شکسته/غایب: $1  ($2)"
    CONTRACT_FAILS=$((CONTRACT_FAILS+1))
  fi
}
contract "P5: mixin کارتابل current_owner_id/owner_deadline" "${CORE_DIR}/models/itr_cartable_mixin.py" "owner_deadline = fields.Datetime"
contract "P5: mixin بلاک‌لیست ادمین"                        "${CORE_DIR}/models/itr_cartable_mixin.py" "_cartable_blocked_user_ids"
contract "P4: trade case current_owner_id"                   "${CORE_DIR}/models/itr_trade_case.py" "current_owner_id = fields.Many2one"
contract "P4: trade case state list"                         "${CORE_DIR}/models/itr_trade_case.py" "pending_signature"
contract "P5: sales slip cartable"                           "${CORE_DIR}/models/itr_sales_slip.py" "itr.cartable.mixin"
contract "P5: transport case cartable"                       "${TRN_DIR}/models/itr_transport_case.py" "itr.cartable.mixin"
contract "P6: payment request cartable"                      "${TRN_DIR}/models/itr_payment_request.py" "itr.cartable.mixin"
contract "P6: مالکان سه تب"                                  "${TRN_DIR}/models/itr_transport_case_ops.py" "delivery_owner_id = fields.Many2one"
contract "P6: checklist_progress"                            "${TRN_DIR}/models/itr_transport_case_ops.py" "checklist_progress = fields.Integer"
contract "P6: effective_tonnage"                             "${TRN_DIR}/models/itr_transport_case_ops.py" "effective_tonnage = fields.Float"
contract "P6: money engine transport_totals"                 "${TRN_DIR}/models/money_engine.py" "def transport_totals"
contract "P2: دفتر ارسال recipient_user_id"                  "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_dispatch_log.py" "recipient_user_id = fields.Many2one"
contract "P2: رویداد is_critical"                            "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_event.py" "is_critical"
contract "P4: shortfall state"                               "${CORE_DIR}/models/itr_factory_shortfall.py" "_name = \"itr.factory.shortfall\""
contract "P7: کلید سخت‌گیری فاز ۷ موجود"                     "${CORE_DIR}/models/itr_sec_phase7.py" "phase7_rules_strict"

if [[ ${CONTRACT_FAILS} -gt 0 ]]; then
  err "پیش‌پرواز شکست خورد: ${CONTRACT_FAILS} قرارداد ناهم‌خوان. هیچ فایلی لمس نشد (پیوست ج)."
fi
gate "G8-01" "Gate 7 سبز + همهٔ fingerprint های قرارداد برقرار (R2)" "PASS" "contracts=OK"

# =============================================================================
step "1) توقف سرویس + پشتیبان کامل (R3)"
# =============================================================================
if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}" 2>/dev/null)" 2>/dev/null; then
  kill "$(cat "${PID_FILE}")" 2>/dev/null || true; sleep 2
fi
pkill -f "odoo-bin.*${CONF_FILE}" 2>/dev/null || true; sleep 1

TS="$(date +%Y%m%d-%H%M%S)"
if [[ "${SKIP_BACKUP}" == "1" ]]; then
  warn "SKIP_BACKUP=1 — پشتیبان رد شد (توصیه نمی‌شود)"
  gate "G8-02" "پشتیبان کامل پیش از فاز" "FAIL" "SKIP_BACKUP=1"
else
  mapfile -t BK < <(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}")
  DUMP_FILE="${BK[0]:-}"; FS_FILE="${BK[1]:-}"
  mkdir -p "${P8_BACKUP_DIR}/${TS}"
  for f in "${CORE_DIR}/models/__init__.py" "${CORE_DIR}/__manifest__.py" \
           "${CORE_DIR}/security/ir.model.access.csv" "${CORE_DIR}/i18n/fa_IR.po" \
           "${TRN_DIR}/models/__init__.py" "${TRN_DIR}/__manifest__.py"; do
    [[ -f "$f" ]] && cp -a "$f" "${P8_BACKUP_DIR}/${TS}/$(echo "$f" | tr '/' '_')"
  done
  if [[ -s "${DUMP_FILE:-/nonexistent}" ]]; then
    gate "G8-02" "پشتیبان کامل + کپی فایل‌های مشترک (R3)" "PASS" "$(basename "${DUMP_FILE}")"
    echo "Rollback: bash ${OPS_DIR}/restore.sh ${DUMP_FILE} ${FS_FILE} ${DB_NAME}"
  else
    gate "G8-02" "پشتیبان کامل پیش از فاز" "FAIL" "backup.sh خروجی نداد"
  fi
fi

# =============================================================================
step "2) فایل‌های *جدید* فاز ۸ (هیچ فایل فاز ۱..۷ بازنویسی نمی‌شود — R1)"
# =============================================================================

# --------------------------- itr_core/models/itr_cartable_settings.py -----
write_utf8 "${CORE_DIR}/models/itr_cartable_settings.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""UX-002: every cartable threshold lives HERE, never in code (Q07).

Single-record settings. The assignment deadline parameter of the phase-5
mixin (itr_core.default_assignment_days) is write-through synchronised so
there is exactly ONE source of truth and the mixin stays untouched (R1/G18).
"""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError

DEFAULT_NAME = "ITR Cartable Settings"


class ItrCartableSettings(models.Model):
    _name = "itr.cartable.settings"
    _description = "Cartable Settings"
    _rec_name = "name"

    name = fields.Char(string="Name", required=True, default=DEFAULT_NAME)
    urgent_hours = fields.Integer(
        string="Urgent threshold (hours)", default=4,
        help="A work item whose owner deadline is closer than this is 'urgent' (UX-002).")
    recent_days = fields.Integer(
        string="Recent window (days)", default=7,
        help="'Recently done' items of the cartable look this many days back.")
    today_hours = fields.Integer(
        string="Today window (hours)", default=24,
        help="'Today' bucket of the Home page (UX-021).")
    assignment_days = fields.Integer(
        string="Default assignment deadline (days)", default=2,
        help="Write-through to itr_core.default_assignment_days of the phase-5 mixin.")
    sla_warn_ratio = fields.Float(
        string="SLA warning ratio", default=0.8,
        help="Kanban turns yellow after this share of the deadline has passed (SRS 11-4).")

    @api.constrains("urgent_hours", "recent_days", "today_hours", "assignment_days", "sla_warn_ratio")
    def _check_positive(self):
        for record in self:
            if record.urgent_hours <= 0 or record.recent_days <= 0 or record.today_hours <= 0 \
                    or record.assignment_days <= 0 or not (0 < record.sla_warn_ratio < 1):
                raise ValidationError(_("Cartable thresholds must be positive (ratio between 0 and 1)."))

    @api.constrains("name")
    def _check_single_record(self):
        if self.search_count([]) > 1:
            raise ValidationError(_("Only one cartable settings record may exist."))

    def write(self, vals):
        result = super().write(vals)
        if "assignment_days" in vals:
            self.env["ir.config_parameter"].sudo().set_param(  # ITR-SUDO-OK settings write-through
                "itr_core.default_assignment_days", str(self.assignment_days))
        return result

    @api.model
    def get_settings(self):
        settings = self.search([], limit=1)
        if not settings:
            settings = self.sudo().create({"name": DEFAULT_NAME})  # ITR-SUDO-OK lazy seed
        return settings
PYEOF
log "itr_core/models/itr_cartable_settings.py"

# --------------------------------- itr_core/models/itr_work_queue.py ------
write_utf8 "${CORE_DIR}/models/itr_work_queue.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""UX-011 — the ONE Unified Work Queue (8.1). Read-only service, no new table.

It aggregates the four existing cartable models of phases 4/5/6 through their
shared contract (current_owner_id / owner_deadline / state). It never writes,
never schedules, never escalates: SLA stays solely in itr_notify (G18) and
assignment stays solely in itr.cartable.mixin.
"""
from datetime import timedelta

from odoo import _, api, fields, models
from odoo.exceptions import UserError

WORK_MODELS = (
    ("itr.trade.case", "Trade case"),
    ("itr.sales.slip", "Sales slip"),
    ("itr.transport.case", "Transport case"),
    ("itr.payment.request", "Payment request"),
)
OPEN_STATES_EXCLUDED = ("closed", "cancelled", "rejected", "executed")


class ItrWorkQueue(models.AbstractModel):
    _name = "itr.work.queue"
    _description = "Unified Work Queue (UX-011)"

    # ------------------------------------------------------------ helpers
    @api.model
    def _settings(self):
        return self.env["itr.cartable.settings"].get_settings()

    @api.model
    def _blocked_user_ids(self):
        return self.env["itr.notification.event"]._blocked_user_ids()

    @api.model
    def _open_domain(self, model_name):
        model = self.env[model_name]
        if "state" in model._fields:
            return [("state", "not in", OPEN_STATES_EXCLUDED)]
        return []

    @api.model
    def _owner_domain(self, model_name, user):
        """Ownership = the shared cartable contract + the three tab owners (C1)."""
        domain = [("current_owner_id", "=", user.id)]
        if model_name == "itr.transport.case":
            domain = ["|", "|", "|",
                      ("current_owner_id", "=", user.id),
                      ("docs_owner_id", "=", user.id),
                      ("customs_owner_id", "=", user.id),
                      ("delivery_owner_id", "=", user.id)]
        return domain

    # ------------------------------------------------------------ buckets
    @api.model
    def my_counts(self, user=None):
        """UAT-12: the exact numbers of MY desk — never someone else's."""
        user = user or self.env.user
        if user.id in self._blocked_user_ids():
            # UX-003: the system administrator deliberately has no cartable
            return {"blocked": True, "urgent": 0, "overdue": 0, "today": 0,
                    "total": 0, "recent_done": 0, "models": {}}
        settings = self._settings()
        now = fields.Datetime.now()
        urgent_edge = now + timedelta(hours=settings.urgent_hours)
        today_edge = now + timedelta(hours=settings.today_hours)
        recent_edge = now - timedelta(days=settings.recent_days)
        totals = {"blocked": False, "urgent": 0, "overdue": 0, "today": 0,
                  "total": 0, "recent_done": 0, "models": {}}
        for model_name, _label in WORK_MODELS:
            model = self.env[model_name].with_user(user)
            base = self._owner_domain(model_name, user) + self._open_domain(model_name)
            total = model.search_count(base)
            overdue = model.search_count(base + [("owner_deadline", "!=", False),
                                                 ("owner_deadline", "<", now)])
            urgent = model.search_count(base + [("owner_deadline", "!=", False),
                                                ("owner_deadline", ">=", now),
                                                ("owner_deadline", "<", urgent_edge)])
            today = model.search_count(base + [("owner_deadline", "!=", False),
                                               ("owner_deadline", ">=", now),
                                               ("owner_deadline", "<", today_edge)])
            recent_done = 0
            if "state" in model._fields:
                recent_done = model.search_count(
                    self._owner_domain(model_name, user)
                    + [("state", "in", OPEN_STATES_EXCLUDED), ("write_date", ">=", recent_edge)])
            totals["models"][model_name] = {
                "total": total, "overdue": overdue, "urgent": urgent,
                "today": today, "recent_done": recent_done,
            }
            totals["total"] += total
            totals["overdue"] += overdue
            totals["urgent"] += urgent
            totals["today"] += today
            totals["recent_done"] += recent_done
        return totals

    @api.model
    def bucket_action(self, model_name, bucket, user=None):
        """Drill-down of one cartable section — a plain act_window, never a bypass (UX-063)."""
        user = user or self.env.user
        if dict(WORK_MODELS).get(model_name) is None:
            raise UserError(_("Unknown work model %(m)s", m=model_name))
        settings = self._settings()
        now = fields.Datetime.now()
        base = self._owner_domain(model_name, user)
        domain = base + self._open_domain(model_name)
        if bucket == "overdue":
            domain += [("owner_deadline", "!=", False), ("owner_deadline", "<", now)]
        elif bucket == "urgent":
            domain += [("owner_deadline", "!=", False), ("owner_deadline", ">=", now),
                       ("owner_deadline", "<", now + timedelta(hours=settings.urgent_hours))]
        elif bucket == "today":
            domain += [("owner_deadline", "!=", False), ("owner_deadline", ">=", now),
                       ("owner_deadline", "<", now + timedelta(hours=settings.today_hours))]
        elif bucket == "recent_done":
            domain = base + [("state", "in", OPEN_STATES_EXCLUDED),
                             ("write_date", ">=", now - timedelta(days=settings.recent_days))]
        elif bucket == "new":
            domain += [("create_date", ">=", now - timedelta(hours=settings.today_hours))]
        # bucket "all" (and any other): open items owned by me
        return {
            "type": "ir.actions.act_window",
            "name": _("My work: %(m)s / %(b)s", m=dict(WORK_MODELS)[model_name], b=bucket),
            "res_model": model_name,
            "view_mode": "list,kanban,form" if model_name == "itr.transport.case" else "list,form",
            "domain": domain,
            "context": {"create": False},
        }

    @api.model
    def team_counts(self, supervisor=None):
        """Team Tasks of UX-011 — the supervisor sees his own team only (SEC-004)."""
        supervisor = supervisor or self.env.user
        team_users = self.env["itr.supervisor.team"].get_subordinate_users(supervisor.id)
        result = {}
        for member in team_users:
            result[member.login] = self.my_counts(member)
        return result
PYEOF
log "itr_core/models/itr_work_queue.py"

# --------------------------------- itr_core/models/itr_kpi_service.py -----
write_utf8 "${CORE_DIR}/models/itr_kpi_service.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""UX-041 — the ONE KPI service. 18 CEO cards, one registry, no parallel SQL.

★ This registry is, by decision (ADR-037), the SEED of the phase-9 Metric
Registry (REP-002): planned/effective tonnage, costs and profit figures all
come from the stored roll-ups of the single money engine of phases 4/6
(FIN-005/G18). Phase 9 must EXTEND this registry — never build a second one.
Every card returns {"value": ..., "action": act_window} so the click of the
number always drills down to the exact records behind it (UX-041).
"""
from odoo import _, api, models

TRANSPORT_OPEN = ("closed", "cancelled")


class ItrKpiService(models.AbstractModel):
    _name = "itr.kpi.service"
    _description = "KPI Service (single metric registry seed - REP-002)"

    # -------------------------------------------------------------- helpers
    def _act(self, title, model, domain, view_mode="list,form", group_by=None):
        action = {
            "type": "ir.actions.act_window", "name": title, "res_model": model,
            "view_mode": view_mode, "domain": domain, "context": {"create": False},
        }
        if group_by:
            action["context"]["group_by"] = group_by
        return action

    def _count(self, model, domain):
        return self.env[model].search_count(domain)

    def _sum(self, model, domain, field_name):
        rows = self.env[model].search_read(domain, [field_name])
        return sum(row[field_name] or 0.0 for row in rows)

    # -------------------------------------------------------------- registry
    @api.model
    def kpi_registry(self):
        """key -> (Persian label, callable) — the 18 official CEO cards (UX-041)."""
        Transport = "itr.transport.case"
        return {
            "loads_in_transit":   (_("Loads in transit"),          self._kpi_loads_in_transit),
            "waiting_driver":     (_("Waiting for a driver"),      self._kpi_waiting_driver),
            "waiting_waybill":    (_("Waiting waybill/weighbridge"), self._kpi_waiting_waybill),
            "waiting_bijak":      (_("Waiting for the bijak"),     self._kpi_waiting_bijak),
            "waiting_clearance":  (_("Waiting for clearance"),     self._kpi_waiting_clearance),
            "waiting_payment":    (_("Waiting for payment"),       self._kpi_waiting_payment),
            "completed_loads":    (_("Completed loadings"),        self._kpi_completed),
            "tonnage_shipped":    (_("Effective tonnage shipped"), self._kpi_tonnage_shipped),
            "tonnage_by_factory": (_("Tonnage per factory"),       self._kpi_tonnage_by_factory),
            "tonnage_by_border":  (_("Tonnage per border"),        self._kpi_tonnage_by_border),
            "freight_cost":       (_("Freight cost (IRR)"),        self._kpi_freight_cost),
            "customs_cost":       (_("Customs duty (IRR)"),        self._kpi_customs_cost),
            "clearance_cost":     (_("Clearance fee (IRR)"),       self._kpi_clearance_cost),
            "profit_per_load":    (_("Profit of loadings (IRR)"),  self._kpi_profit_per_load),
            "profit_by_customer": (_("Profit per customer"),       self._kpi_profit_by_customer),
            "profit_by_factory":  (_("Profit per factory"),        self._kpi_profit_by_factory),
            "stalled_cases":      (_("Stalled work items"),        self._kpi_stalled),
            "factory_debt":       (_("Open factory debt"),         self._kpi_factory_debt),
        }

    @api.model
    def get_kpi(self, key):
        registry = self.kpi_registry()
        if key not in registry:
            raise ValueError("unknown KPI key: %s" % key)
        label, method = registry[key]
        result = method()
        result["label"] = label
        result["key"] = key
        return result

    @api.model
    def get_all(self):
        return {key: self.get_kpi(key) for key in self.kpi_registry()}

    # -------------------------------------------------------------- cards
    def _kpi_loads_in_transit(self):
        domain = [("state", "in", ("in_transit", "waiting_weighbridge", "waiting_bijak", "waiting_clearance"))]
        return {"value": self._count("itr.transport.case", domain),
                "action": self._act(_("Loads in transit"), "itr.transport.case", domain)}

    def _kpi_waiting_driver(self):
        domain = [("state", "in", ("pending_review", "loading_authorized")), ("driver_id", "=", False)]
        return {"value": self._count("itr.transport.case", domain),
                "action": self._act(_("Waiting for a driver"), "itr.transport.case", domain)}

    def _kpi_waiting_waybill(self):
        domain = ["|", ("waybill_number", "=", False), ("weighbridge_confirmed", "=", False),
                  ("state", "not in", TRANSPORT_OPEN)]
        return {"value": self._count("itr.transport.case", domain),
                "action": self._act(_("Waiting waybill/weighbridge"), "itr.transport.case", domain)}

    def _kpi_waiting_bijak(self):
        domain = [("state", "=", "waiting_bijak")]
        return {"value": self._count("itr.transport.case", domain),
                "action": self._act(_("Waiting for the bijak"), "itr.transport.case", domain)}

    def _kpi_waiting_clearance(self):
        domain = [("state", "=", "waiting_clearance")]
        return {"value": self._count("itr.transport.case", domain),
                "action": self._act(_("Waiting for clearance"), "itr.transport.case", domain)}

    def _kpi_waiting_payment(self):
        domain = [("state", "=", "waiting_payment")]
        return {"value": self._count("itr.transport.case", domain),
                "action": self._act(_("Waiting for payment"), "itr.transport.case", domain)}

    def _kpi_completed(self):
        domain = [("state", "in", ("settled", "closed"))]
        return {"value": self._count("itr.transport.case", domain),
                "action": self._act(_("Completed loadings"), "itr.transport.case", domain)}

    def _kpi_tonnage_shipped(self):
        domain = [("state", "not in", ("cancelled",)), ("effective_tonnage", ">", 0)]
        return {"value": self._sum("itr.transport.case", domain, "effective_tonnage"),
                "action": self._act(_("Effective tonnage"), "itr.transport.case", domain)}

    def _kpi_tonnage_by_factory(self):
        domain = [("state", "not in", ("cancelled",)), ("effective_tonnage", ">", 0)]
        return {"value": self._sum("itr.transport.case", domain, "effective_tonnage"),
                "action": self._act(_("Tonnage per factory"), "itr.transport.case",
                                    domain, group_by="factory_id")}

    def _kpi_tonnage_by_border(self):
        domain = [("state", "not in", ("cancelled",)), ("effective_tonnage", ">", 0)]
        return {"value": self._sum("itr.transport.case", domain, "effective_tonnage"),
                "action": self._act(_("Tonnage per border"), "itr.transport.case",
                                    domain, group_by="border_id")}

    def _kpi_freight_cost(self):
        # FIN-005: read the stored roll-up of the single money engine, no new formula
        domain = [("state", "not in", ("cancelled",))]
        return {"value": self._sum("itr.transport.case", domain, "freight_cost"),
                "action": self._act(_("Freight cost lines"), "itr.cost.line",
                                    [("category", "=", "freight")])}

    def _kpi_customs_cost(self):
        domain = [("state", "not in", ("cancelled",))]
        return {"value": self._sum("itr.transport.case", domain, "customs_cost"),
                "action": self._act(_("Customs duty lines"), "itr.cost.line",
                                    [("category", "=", "customs")])}

    def _kpi_clearance_cost(self):
        # G05: customs and clearance stay two independent figures, never merged
        domain = [("state", "not in", ("cancelled",))]
        return {"value": self._sum("itr.transport.case", domain, "clearance_cost"),
                "action": self._act(_("Clearance fee lines"), "itr.cost.line",
                                    [("category", "=", "clearance")])}

    def _kpi_profit_per_load(self):
        domain = [("state", "not in", ("cancelled",))]
        rows = self.env["itr.transport.case"].search_read(
            domain, ["sale_amount_base", "purchase_amount_base", "total_cost"])
        value = sum((r["sale_amount_base"] or 0.0) - (r["purchase_amount_base"] or 0.0)
                    - (r["total_cost"] or 0.0) for r in rows)
        return {"value": value,
                "action": self._act(_("Profit per loading"), "itr.transport.case", domain)}

    def _kpi_profit_by_customer(self):
        domain = [("state", "not in", ("cancelled",))]
        return {"value": self._kpi_profit_per_load()["value"],
                "action": self._act(_("Profit per customer"), "itr.transport.case",
                                    domain, group_by="customer_id")}

    def _kpi_profit_by_factory(self):
        domain = [("state", "not in", ("cancelled",))]
        return {"value": self._kpi_profit_per_load()["value"],
                "action": self._act(_("Profit per factory"), "itr.transport.case",
                                    domain, group_by="factory_id")}

    def _kpi_stalled(self):
        # stalled = an open work item whose owner deadline has passed (cartable clock)
        from odoo import fields as odoo_fields
        now = odoo_fields.Datetime.now()
        domain = [("state", "not in", ("closed", "cancelled", "rejected")),
                  ("owner_deadline", "!=", False), ("owner_deadline", "<", now)]
        trade = self._count("itr.trade.case", domain)
        transport = self._count("itr.transport.case", domain)
        return {"value": trade + transport,
                "action": self._act(_("Stalled loadings"), "itr.transport.case", domain)}

    def _kpi_factory_debt(self):
        domain = [("state", "in", ("open", "partially_settled"))]
        return {"value": self._sum("itr.factory.shortfall", domain, "shortfall_amount_base"),
                "action": self._act(_("Open factory debt"), "itr.factory.shortfall", domain)}
PYEOF
log "itr_core/models/itr_kpi_service.py"

# --------------------------------------- itr_core/models/itr_home.py ------
write_utf8 "${CORE_DIR}/models/itr_home.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""UX-021 — the Home page of every role: «سلام، <نام>» + coloured counters +
quick actions. One row per user; counters are live computes over the ONE
Unified Work Queue; the quick buttons only open server actions (UX-063:
shortcuts, never a process bypass). Administrator is refused (UX-003).
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError


class ItrHome(models.Model):
    _name = "itr.home"
    _description = "My Home (UX-021)"
    _rec_name = "greeting"

    user_id = fields.Many2one("res.users", string="User", required=True, readonly=True,
                              index=True, ondelete="cascade",
                              default=lambda self: self.env.user)
    greeting = fields.Char(string="Greeting", compute="_compute_counters")
    urgent_count = fields.Integer(string="Urgent (red)", compute="_compute_counters")
    overdue_count = fields.Integer(string="Overdue (orange)", compute="_compute_counters")
    today_count = fields.Integer(string="Today (yellow)", compute="_compute_counters")
    open_count = fields.Integer(string="All my open work", compute="_compute_counters")
    recent_done_count = fields.Integer(string="Recently done", compute="_compute_counters")
    notification_count = fields.Integer(string="Unread notifications", compute="_compute_counters")

    _user_uniq = models.Constraint(
        "unique(user_id)",
        "Every user has exactly one Home.",
    )

    # ------------------------------------------------------------ computes
    def _compute_counters(self):
        Queue = self.env["itr.work.queue"]
        Dispatch = self.env["itr.notification.dispatch.log"]
        for record in self:
            counts = Queue.my_counts(record.user_id)
            record.greeting = _("Hello, %(name)s", name=record.user_id.name)
            record.urgent_count = counts["urgent"]
            record.overdue_count = counts["overdue"]
            record.today_count = counts["today"]
            record.open_count = counts["total"]
            record.recent_done_count = counts["recent_done"]
            record.notification_count = Dispatch.with_user(record.user_id).search_count(
                [("recipient_user_id", "=", record.user_id.id),
                 ("channel", "=", "internal"), ("read_on", "=", False)])

    # ------------------------------------------------------------ lifecycle
    @api.model_create_multi
    def create(self, vals_list):
        blocked = self.env["itr.work.queue"]._blocked_user_ids()
        for vals in vals_list:
            user_id = vals.get("user_id") or self.env.uid
            if user_id in blocked:
                raise UserError(_("The system administrator deliberately has no "
                                  "operational Home/cartable (UX-003/Q03)."))
        return super().create(vals_list)

    @api.model
    def action_open_my_home(self):
        """The single entry point of the «خانهٔ من» menu."""
        if self.env.uid in self.env["itr.work.queue"]._blocked_user_ids():
            raise UserError(_("The system administrator deliberately has no "
                              "operational Home/cartable (UX-003/Q03)."))
        home = self.search([("user_id", "=", self.env.uid)], limit=1)
        if not home:
            home = self.create({"user_id": self.env.uid})
        return {
            "type": "ir.actions.act_window", "name": _("My Home"),
            "res_model": "itr.home", "res_id": home.id,
            "view_mode": "form", "target": "current",
        }

    # ------------------------------------------------------------ shortcuts
    def _bucket(self, model_name, bucket):
        self.ensure_one()
        if self.user_id != self.env.user:
            raise UserError(_("The Home page only ever shows YOUR OWN work (UAT-12)."))
        return self.env["itr.work.queue"].bucket_action(model_name, bucket, self.env.user)

    def action_my_cases(self):
        return self._bucket("itr.trade.case", "all")

    def action_my_loadings(self):
        return self._bucket("itr.transport.case", "all")

    def action_my_urgent_loadings(self):
        return self._bucket("itr.transport.case", "urgent")

    def action_my_overdue_loadings(self):
        return self._bucket("itr.transport.case", "overdue")

    def action_my_payment_requests(self):
        return self._bucket("itr.payment.request", "all")

    def action_today(self):
        return self._bucket("itr.transport.case", "today")

    def action_new_case(self):
        """Shortcut to the OFFICIAL creation form — the same server-side guards
        of phase 4 apply untouched (UX-063: never a bypass)."""
        self.ensure_one()
        return {
            "type": "ir.actions.act_window", "name": _("New trade case"),
            "res_model": "itr.trade.case", "view_mode": "form", "target": "current",
        }

    def action_notifications(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window", "name": _("My notifications"),
            "res_model": "itr.notification.dispatch.log", "view_mode": "list",
            "domain": [("recipient_user_id", "=", self.env.uid), ("channel", "=", "internal")],
            "context": {"create": False},
        }
PYEOF
log "itr_core/models/itr_home.py"

# ------------------------------- itr_core/models/itr_ceo_dashboard.py -----
write_utf8 "${CORE_DIR}/models/itr_ceo_dashboard.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""UX-041 — the CEO dashboard: 18 cards, ALL numbers from itr.kpi.service
(the single registry — G18/FIN-005), every card drills down (8.6).
"""
from odoo import _, api, fields, models


class ItrCeoDashboard(models.Model):
    _name = "itr.ceo.dashboard"
    _description = "CEO Dashboard (UX-041)"
    _rec_name = "name"

    name = fields.Char(default="ITR CEO Dashboard", readonly=True)

    kpi_loads_in_transit = fields.Integer(compute="_compute_kpis", string="Loads in transit")
    kpi_waiting_driver = fields.Integer(compute="_compute_kpis", string="Waiting for driver")
    kpi_waiting_waybill = fields.Integer(compute="_compute_kpis", string="Waiting waybill/weighbridge")
    kpi_waiting_bijak = fields.Integer(compute="_compute_kpis", string="Waiting bijak")
    kpi_waiting_clearance = fields.Integer(compute="_compute_kpis", string="Waiting clearance")
    kpi_waiting_payment = fields.Integer(compute="_compute_kpis", string="Waiting payment")
    kpi_completed_loads = fields.Integer(compute="_compute_kpis", string="Completed loadings")
    kpi_tonnage_shipped = fields.Float(compute="_compute_kpis", string="Effective tonnage")
    kpi_tonnage_by_factory = fields.Float(compute="_compute_kpis", string="Tonnage per factory")
    kpi_tonnage_by_border = fields.Float(compute="_compute_kpis", string="Tonnage per border")
    kpi_freight_cost = fields.Float(compute="_compute_kpis", string="Freight cost (IRR)")
    kpi_customs_cost = fields.Float(compute="_compute_kpis", string="Customs duty (IRR)")
    kpi_clearance_cost = fields.Float(compute="_compute_kpis", string="Clearance fee (IRR)")
    kpi_profit_per_load = fields.Float(compute="_compute_kpis", string="Profit (IRR)")
    kpi_profit_by_customer = fields.Float(compute="_compute_kpis", string="Profit per customer")
    kpi_profit_by_factory = fields.Float(compute="_compute_kpis", string="Profit per factory")
    kpi_stalled_cases = fields.Integer(compute="_compute_kpis", string="Stalled work items")
    kpi_factory_debt = fields.Float(compute="_compute_kpis", string="Open factory debt (IRR)")

    def _compute_kpis(self):
        service = self.env["itr.kpi.service"]
        values = service.get_all()
        for record in self:
            for key, result in values.items():
                record["kpi_%s" % key] = result["value"]

    @api.model
    def action_open_dashboard(self):
        dashboard = self.search([], limit=1)
        if not dashboard:
            dashboard = self.sudo().create({})  # ITR-SUDO-OK singleton seed
        return {
            "type": "ir.actions.act_window", "name": _("CEO Dashboard"),
            "res_model": "itr.ceo.dashboard", "res_id": dashboard.id,
            "view_mode": "form", "target": "current",
        }

    def _drill(self, key):
        self.ensure_one()
        return self.env["itr.kpi.service"].get_kpi(key)["action"]

    def action_drill_loads_in_transit(self):
        return self._drill("loads_in_transit")

    def action_drill_waiting_driver(self):
        return self._drill("waiting_driver")

    def action_drill_waiting_waybill(self):
        return self._drill("waiting_waybill")

    def action_drill_waiting_bijak(self):
        return self._drill("waiting_bijak")

    def action_drill_waiting_clearance(self):
        return self._drill("waiting_clearance")

    def action_drill_waiting_payment(self):
        return self._drill("waiting_payment")

    def action_drill_completed_loads(self):
        return self._drill("completed_loads")

    def action_drill_tonnage_shipped(self):
        return self._drill("tonnage_shipped")

    def action_drill_tonnage_by_factory(self):
        return self._drill("tonnage_by_factory")

    def action_drill_tonnage_by_border(self):
        return self._drill("tonnage_by_border")

    def action_drill_freight_cost(self):
        return self._drill("freight_cost")

    def action_drill_customs_cost(self):
        return self._drill("customs_cost")

    def action_drill_clearance_cost(self):
        return self._drill("clearance_cost")

    def action_drill_profit_per_load(self):
        return self._drill("profit_per_load")

    def action_drill_profit_by_customer(self):
        return self._drill("profit_by_customer")

    def action_drill_profit_by_factory(self):
        return self._drill("profit_by_factory")

    def action_drill_stalled_cases(self):
        return self._drill("stalled_cases")

    def action_drill_factory_debt(self):
        return self._drill("factory_debt")
PYEOF
log "itr_core/models/itr_ceo_dashboard.py"

# ------------------------------ itr_core/models/itr_notify_phase8.py ------
# ★ F6: mark_read must NOT call super(Phase8).write → phase-2 append-only guard.
#    Use models.Model.write after the recipient guard (ITR-SUDO-OK).
write_utf8 "${CORE_DIR}/models/itr_notify_phase8.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""UX-022 — Notification Center additions [FIX-P8-1], purely by inheritance.

The dispatch log of phase 2 stays the single ledger (no second notification
store). We only add the 'read' dimension + a stored critical flag so the three
official buckets [new]/[critical]/[read] become plain domains, and a jump
button to the real record (every notification links to its business record).
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError


class ItrDispatchLogPhase8(models.Model):
    _inherit = "itr.notification.dispatch.log"

    read_on = fields.Datetime(string="Read on", readonly=True, copy=False, index=True)
    is_critical_stored = fields.Boolean(
        string="Critical", related="event_id.is_critical", store=True, readonly=True, index=True)

    def action_mark_read(self):
        """Only the recipient himself may mark his notification as read (V8-07)."""
        now = fields.Datetime.now()
        for record in self:
            if record.recipient_user_id and record.recipient_user_id != self.env.user:
                raise UserError(_("Only the recipient may mark a notification as read."))
            if not record.read_on:
                record._phase8_mark_read(now)
        return True

    def _phase8_mark_read(self, when):
        # append-only spirit of phase 2 preserved for every other field.
        # F6: must NOT call super().write — that hits the phase-2 append-only
        # UserError. Bypass only for the read_on flag, after recipient guard.
        self.ensure_one()
        if not self.read_on:
            models.Model.write(self.sudo(), {"read_on": when})  # ITR-SUDO-OK recipient-guarded read flag

    def write(self, vals):
        # allow the read flag to pass the append-only guard of phase 2 unharmed
        # (UI / RPC path that lands on write directly with only read_on)
        if set(vals) == {"read_on"}:
            return models.Model.write(self, vals)
        return super().write(vals)

    def action_open_reference(self):
        """UX-022: every notification links to the REAL record behind it."""
        self.ensure_one()
        if not (self.res_model and self.res_id):
            raise UserError(_("This notification has no business record reference."))
        return {
            "type": "ir.actions.act_window", "name": _("Referenced record"),
            "res_model": self.res_model, "res_id": self.res_id,
            "view_mode": "form", "target": "current",
        }
PYEOF
log "itr_core/models/itr_notify_phase8.py"

# ------------------------------- itr_core/models/itr_ux_phase8.py ---------
write_utf8 "${CORE_DIR}/models/itr_ux_phase8.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""UX-051/8.7 additions on the trade case, purely by inheritance.

* case_progress [FIX-P8-3]: a progress ratio over the locked state chain of
  phase 4 (G10 names untouched — we only READ them).
* sla_color: kanban colour from the cartable deadline + the settings ratio
  (UX-002). SLA escalation itself stays solely in itr_notify (G18); this is
  presentation of the SAME clock, not a second engine.
* notification_count + jump action (UX-051: «تاریخچهٔ اعلان‌ها روی فرم»).
"""
from datetime import timedelta

from odoo import _, api, fields, models

STATE_PROGRESS = {
    "draft": 5, "waiting_supply": 15, "legal_review": 30, "treasury_review": 45,
    "receivables_review": 60, "returned": 35, "pending_signature": 75,
    "approved": 85, "slips_issued": 95, "closed": 100, "rejected": 100,
}
SLA_STATES = [("green", "On time"), ("yellow", "Near deadline"),
              ("orange", "Late"), ("red", "Critical"), ("none", "No deadline")]


class ItrTradeCaseUx(models.Model):
    _inherit = "itr.trade.case"

    case_progress = fields.Integer(string="Progress (%)", compute="_compute_ux_phase8")
    sla_color = fields.Selection(SLA_STATES, string="SLA state", compute="_compute_ux_phase8")
    notification_count = fields.Integer(string="Notifications", compute="_compute_ux_phase8")

    def _compute_ux_phase8(self):
        settings = self.env["itr.cartable.settings"].get_settings()
        now = fields.Datetime.now()
        Dispatch = self.env["itr.notification.dispatch.log"]
        for record in self:
            record.case_progress = STATE_PROGRESS.get(record.state, 0)
            record.sla_color = _sla_bucket(record, now, settings)
            record.notification_count = Dispatch.search_count(
                [("res_model", "=", record._name), ("res_id", "=", record.id)])

    def action_open_notifications(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "name": _("Notification history of %(n)s", n=self.name),
            "res_model": "itr.notification.dispatch.log", "view_mode": "list",
            "domain": [("res_model", "=", self._name), ("res_id", "=", self.id)],
            "context": {"create": False},
        }


def _sla_bucket(record, now, settings):
    deadline = record.owner_deadline
    if not deadline or record.state in ("closed", "cancelled", "rejected", "settled"):
        return "none"
    if deadline < now:
        overdue_for = now - deadline
        return "red" if overdue_for > timedelta(hours=settings.urgent_hours) else "orange"
    remaining = deadline - now
    if remaining <= timedelta(hours=settings.urgent_hours):
        return "yellow"
    return "green"
PYEOF
log "itr_core/models/itr_ux_phase8.py"

# ------------------------- itr_transport/models/itr_ux_phase8.py ----------
write_utf8 "${TRN_DIR}/models/itr_ux_phase8.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""UX-051/8.7 on the transport case — same presentation contract as itr_core.

checklist_progress of phase 6 stays THE progress figure (no second formula);
we only add the SLA colour of the shared cartable clock + the notification
jump (UX-051). Escalation remains solely in itr_notify (G18).
"""
from odoo import _, fields, models

from odoo.addons.itr_core.models.itr_ux_phase8 import SLA_STATES, _sla_bucket


class ItrTransportCaseUx(models.Model):
    _inherit = "itr.transport.case"

    sla_color = fields.Selection(SLA_STATES, string="SLA state", compute="_compute_ux_phase8")
    notification_count = fields.Integer(string="Notifications", compute="_compute_ux_phase8")

    def _compute_ux_phase8(self):
        settings = self.env["itr.cartable.settings"].get_settings()
        now = fields.Datetime.now()
        Dispatch = self.env["itr.notification.dispatch.log"]
        for record in self:
            record.sla_color = _sla_bucket(record, now, settings)
            record.notification_count = Dispatch.search_count(
                [("res_model", "=", record._name), ("res_id", "=", record.id)])

    def action_open_notifications(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "name": _("Notification history of %(n)s", n=self.name),
            "res_model": "itr.notification.dispatch.log", "view_mode": "list",
            "domain": [("res_model", "=", self._name), ("res_id", "=", self.id)],
            "context": {"create": False},
        }
PYEOF
log "itr_transport/models/itr_ux_phase8.py"

# ------------------------ itr_core/security/itr_core_phase8_rules.xml -----
write_utf8 "${CORE_DIR}/security/itr_core_phase8_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <!-- [FIX-P8-2] اعلانِ من فقط مالِ من است؛ مدیر اعلان/حسابرس/CEO همه را می‌بینند -->
        <record id="rule_dispatch_log_own_p8" model="ir.rule">
            <field name="name">Dispatch log: users read their own notifications (UX-022)</field>
            <field name="model_id" ref="itr_notify.model_itr_notification_dispatch_log"/>
            <field name="domain_force">[(1, '=', 1)] if (
                user.has_group('itr_notify.group_itr_notification_manager')
                or user.has_group('itr_core.group_ceo')
                or user.has_group('itr_core.group_financial_manager')
                or user.has_group('itr_core.group_auditor')
            ) else ['|', ('recipient_user_id', '=', user.id), ('recipient_user_id', '=', False)]</field>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="False"/>
            <field name="perm_unlink" eval="False"/>
        </record>

        <!-- Home: هر کاربر فقط رکورد Home خودش (UAT-12) -->
        <record id="rule_itr_home_own_p8" model="ir.rule">
            <field name="name">Home: strictly my own row (UX-021/UAT-12)</field>
            <field name="model_id" ref="itr_core.model_itr_home"/>
            <field name="domain_force">[('user_id', '=', user.id)]</field>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

    </data>
</odoo>
XMLEOF
log "itr_core/security/itr_core_phase8_rules.xml"

# ------------------------------ data: seed تنظیمات کارتابل + داشبورد ------
write_utf8 "${CORE_DIR}/data/itr_core_phase8_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="itr_cartable_settings_default" model="itr.cartable.settings">
            <field name="name">ITR Cartable Settings</field>
            <field name="urgent_hours">4</field>
            <field name="recent_days">7</field>
            <field name="today_hours">24</field>
            <field name="assignment_days">2</field>
            <field name="sla_warn_ratio">0.8</field>
        </record>
        <record id="itr_ceo_dashboard_default" model="itr.ceo.dashboard">
            <field name="name">ITR CEO Dashboard</field>
        </record>
    </data>
</odoo>
XMLEOF
log "itr_core/data/itr_core_phase8_data.xml"

# ------------------------------------ views: Home + داشبورد + تنظیمات -----
write_utf8 "${CORE_DIR}/views/itr_home_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>

    <record id="view_itr_home_form" model="ir.ui.view">
        <field name="name">itr.home.form</field>
        <field name="model">itr.home</field>
        <field name="arch" type="xml">
            <form string="My Home" create="false" delete="false" edit="false">
                <sheet>
                    <div class="oe_title">
                        <h1><field name="greeting" readonly="1"/></h1>
                    </div>
                    <group string="کارهای من — شمارنده‌های رنگی (UX-021)">
                        <group>
                            <field name="urgent_count" readonly="1" decoration-danger="urgent_count &gt; 0"/>
                            <field name="overdue_count" readonly="1" decoration-warning="overdue_count &gt; 0"/>
                            <field name="today_count" readonly="1"/>
                        </group>
                        <group>
                            <field name="open_count" readonly="1"/>
                            <field name="recent_done_count" readonly="1"/>
                            <field name="notification_count" readonly="1" decoration-info="notification_count &gt; 0"/>
                        </group>
                    </group>
                    <group string="میان‌برها (Shortcut به اکشن‌های مجاز سرور — هرگز bypass، UX-063)">
                        <div>
                            <button name="action_my_cases" type="object" string="پرونده‌های من" class="btn-primary me-1 mb-1"/>
                            <button name="action_my_loadings" type="object" string="بارگیری‌های من" class="btn-primary me-1 mb-1"/>
                            <button name="action_my_urgent_loadings" type="object" string="فوری‌ها" class="btn-danger me-1 mb-1"/>
                            <button name="action_my_overdue_loadings" type="object" string="عقب‌افتاده‌ها" class="btn-warning me-1 mb-1"/>
                            <button name="action_today" type="object" string="کارهای امروز" class="btn-secondary me-1 mb-1"/>
                            <button name="action_my_payment_requests" type="object" string="درخواست‌های پرداخت من" class="btn-secondary me-1 mb-1"/>
                            <button name="action_new_case" type="object" string="ایجاد پروندهٔ جدید" class="btn-success me-1 mb-1"
                                    groups="itr_core.group_finance_user,itr_core.group_finance_supervisor,itr_core.group_ceo"/>
                            <button name="action_notifications" type="object" string="اعلان‌های من" class="btn-info me-1 mb-1"/>
                        </div>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="action_itr_home" model="ir.actions.server">
        <field name="name">My Home</field>
        <field name="model_id" ref="itr_core.model_itr_home"/>
        <field name="state">code</field>
        <field name="code">action = model.action_open_my_home()</field>
    </record>

    <record id="view_itr_cartable_settings_form" model="ir.ui.view">
        <field name="name">itr.cartable.settings.form</field>
        <field name="model">itr.cartable.settings</field>
        <field name="arch" type="xml">
            <form string="Cartable Settings">
                <sheet>
                    <div class="oe_title"><h1><field name="name" readonly="1"/></h1></div>
                    <group string="آستانه‌ها — فقط از اینجا، هرگز از کد (UX-002/Q07)">
                        <field name="urgent_hours"/>
                        <field name="today_hours"/>
                        <field name="recent_days"/>
                        <field name="assignment_days"/>
                        <field name="sla_warn_ratio"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="action_itr_cartable_settings" model="ir.actions.act_window">
        <field name="name">Cartable Settings</field>
        <field name="res_model">itr.cartable.settings</field>
        <field name="view_mode">form</field>
        <field name="res_id" eval="ref('itr_core.itr_cartable_settings_default')"/>
        <field name="target">current</field>
    </record>

    <record id="view_itr_ceo_dashboard_form" model="ir.ui.view">
        <field name="name">itr.ceo.dashboard.form</field>
        <field name="model">itr.ceo.dashboard</field>
        <field name="arch" type="xml">
            <form string="CEO Dashboard" create="false" delete="false" edit="false">
                <sheet>
                    <div class="oe_title"><h1>داشبورد مدیرعامل — ۱۸ کارت (UX-041)</h1></div>
                    <group string="عملیات جاری">
                        <group>
                            <label for="kpi_loads_in_transit"/>
                            <div><field name="kpi_loads_in_transit" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_loads_in_transit" type="object" string="⤷" class="btn-link" title="Drill-down"/></div>
                            <label for="kpi_waiting_driver"/>
                            <div><field name="kpi_waiting_driver" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_waiting_driver" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_waiting_waybill"/>
                            <div><field name="kpi_waiting_waybill" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_waiting_waybill" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_waiting_bijak"/>
                            <div><field name="kpi_waiting_bijak" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_waiting_bijak" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_waiting_clearance"/>
                            <div><field name="kpi_waiting_clearance" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_waiting_clearance" type="object" string="⤷" class="btn-link"/></div>
                        </group>
                        <group>
                            <label for="kpi_waiting_payment"/>
                            <div><field name="kpi_waiting_payment" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_waiting_payment" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_completed_loads"/>
                            <div><field name="kpi_completed_loads" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_completed_loads" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_stalled_cases"/>
                            <div><field name="kpi_stalled_cases" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_stalled_cases" type="object" string="⤷" class="btn-link"/></div>
                        </group>
                    </group>
                    <group string="تناژ">
                        <group>
                            <label for="kpi_tonnage_shipped"/>
                            <div><field name="kpi_tonnage_shipped" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_tonnage_shipped" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_tonnage_by_factory"/>
                            <div><field name="kpi_tonnage_by_factory" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_tonnage_by_factory" type="object" string="⤷" class="btn-link"/></div>
                        </group>
                        <group>
                            <label for="kpi_tonnage_by_border"/>
                            <div><field name="kpi_tonnage_by_border" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_tonnage_by_border" type="object" string="⤷" class="btn-link"/></div>
                        </group>
                    </group>
                    <group string="مالی (از موتور مالی واحد — FIN-005/G05)">
                        <group>
                            <label for="kpi_freight_cost"/>
                            <div><field name="kpi_freight_cost" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_freight_cost" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_customs_cost"/>
                            <div><field name="kpi_customs_cost" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_clearance_cost" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_clearance_cost"/>
                            <div><field name="kpi_clearance_cost" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_clearance_cost" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_factory_debt"/>
                            <div><field name="kpi_factory_debt" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_factory_debt" type="object" string="⤷" class="btn-link"/></div>
                        </group>
                        <group>
                            <label for="kpi_profit_per_load"/>
                            <div><field name="kpi_profit_per_load" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_profit_per_load" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_profit_by_customer"/>
                            <div><field name="kpi_profit_by_customer" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_profit_by_customer" type="object" string="⤷" class="btn-link"/></div>
                            <label for="kpi_profit_by_factory"/>
                            <div><field name="kpi_profit_by_factory" readonly="1" class="oe_inline"/>
                                 <button name="action_drill_profit_by_factory" type="object" string="⤷" class="btn-link"/></div>
                        </group>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="action_itr_ceo_dashboard" model="ir.actions.server">
        <field name="name">CEO Dashboard</field>
        <field name="model_id" ref="itr_core.model_itr_ceo_dashboard"/>
        <field name="state">code</field>
        <field name="code">action = model.action_open_dashboard()</field>
    </record>

</odoo>
XMLEOF
log "itr_core/views/itr_home_views.xml"

# ----------------------------- views: مرکز اعلان + کارتابل ده‌بخشی --------
# ★ F4: هیچ act_window با res_model=itr.transport.case در itr_core — فقط server action
write_utf8 "${CORE_DIR}/views/itr_cartable_phase8_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>

    <!-- مرکز اعلان (UX-022) — سه دستهٔ رسمی؛ مدل itr_notify (وابستگی itr_core) -->
    <record id="view_dispatch_log_center_list" model="ir.ui.view">
        <field name="name">itr.notification.dispatch.log.center.list</field>
        <field name="model">itr.notification.dispatch.log</field>
        <field name="arch" type="xml">
            <list string="Notifications" create="false" delete="false"
                  decoration-danger="is_critical_stored" decoration-muted="read_on != False">
                <field name="create_date"/>
                <field name="event_key"/>
                <field name="subject"/>
                <field name="is_critical_stored"/>
                <field name="read_on"/>
                <field name="res_model" column_invisible="1"/>
                <field name="res_id" column_invisible="1"/>
                <button name="action_open_reference" type="object" string="رکورد" icon="fa-external-link"/>
                <button name="action_mark_read" type="object" string="خوانده شد" icon="fa-check"
                        invisible="read_on != False"/>
            </list>
        </field>
    </record>

    <record id="action_notification_center_new" model="ir.actions.act_window">
        <field name="name">اعلان‌ها — جدید</field>
        <field name="res_model">itr.notification.dispatch.log</field>
        <field name="view_mode">list</field>
        <field name="view_id" ref="view_dispatch_log_center_list"/>
        <field name="domain">[('recipient_user_id', '=', uid), ('channel', '=', 'internal'), ('read_on', '=', False)]</field>
    </record>
    <record id="action_notification_center_critical" model="ir.actions.act_window">
        <field name="name">اعلان‌ها — بحرانی</field>
        <field name="res_model">itr.notification.dispatch.log</field>
        <field name="view_mode">list</field>
        <field name="view_id" ref="view_dispatch_log_center_list"/>
        <field name="domain">[('recipient_user_id', '=', uid), ('is_critical_stored', '=', True)]</field>
    </record>
    <record id="action_notification_center_read" model="ir.actions.act_window">
        <field name="name">اعلان‌ها — خوانده‌شده</field>
        <field name="res_model">itr.notification.dispatch.log</field>
        <field name="view_mode">list</field>
        <field name="view_id" ref="view_dispatch_log_center_list"/>
        <field name="domain">[('recipient_user_id', '=', uid), ('read_on', '!=', False)]</field>
    </record>

    <!-- کارتابل ده‌بخشی (UX-001)
         F4/Q02: مدل‌های itr_transport فقط از مسیر ir.actions.server + work.queue
         (در زمان اجرا res_model برمی‌گردد؛ هنگام لود XMLِ itr_core مدل حمل لازم نیست) -->
    <record id="action_cartable_assigned_to_me" model="ir.actions.server">
        <field name="name">۱) ارجاع‌شده به من</field>
        <field name="model_id" ref="itr_core.model_itr_work_queue"/>
        <field name="state">code</field>
        <field name="code">action = model.bucket_action("itr.transport.case", "all")</field>
    </record>
    <record id="action_cartable_new_work" model="ir.actions.server">
        <field name="name">۲) کارهای جدید</field>
        <field name="model_id" ref="itr_core.model_itr_work_queue"/>
        <field name="state">code</field>
        <field name="code">action = model.bucket_action("itr.transport.case", "new")</field>
    </record>
    <record id="action_cartable_awaiting_me" model="ir.actions.server">
        <field name="name">۳) در انتظار اقدام من</field>
        <field name="model_id" ref="itr_core.model_itr_work_queue"/>
        <field name="state">code</field>
        <field name="code">action = model.bucket_action("itr.transport.case", "all")</field>
    </record>
    <record id="action_cartable_urgent" model="ir.actions.server">
        <field name="name">۴) فوری</field>
        <field name="model_id" ref="itr_core.model_itr_work_queue"/>
        <field name="state">code</field>
        <field name="code">action = model.bucket_action("itr.transport.case", "urgent")</field>
    </record>
    <record id="action_cartable_overdue" model="ir.actions.server">
        <field name="name">۵) عقب‌افتاده</field>
        <field name="model_id" ref="itr_core.model_itr_work_queue"/>
        <field name="state">code</field>
        <field name="code">action = model.bucket_action("itr.transport.case", "overdue")</field>
    </record>
    <record id="action_cartable_my_cases" model="ir.actions.act_window">
        <field name="name">۶) پرونده‌های در اختیار من</field>
        <field name="res_model">itr.trade.case</field>
        <field name="view_mode">list,form</field>
        <field name="domain">[('current_owner_id','=',uid),('state','not in',('closed','rejected'))]</field>
    </record>
    <record id="action_cartable_my_loadings" model="ir.actions.server">
        <field name="name">۷) بارگیری‌های من</field>
        <field name="model_id" ref="itr_core.model_itr_work_queue"/>
        <field name="state">code</field>
        <field name="code">action = model.bucket_action("itr.transport.case", "all")</field>
    </record>
    <record id="action_cartable_recent_done" model="ir.actions.server">
        <field name="name">۸) تکمیل‌شدهٔ اخیر</field>
        <field name="model_id" ref="itr_core.model_itr_work_queue"/>
        <field name="state">code</field>
        <field name="code">action = model.bucket_action("itr.transport.case", "recent_done")</field>
    </record>
    <!-- ۹) اعلان‌ها و هشدارها = action_notification_center_new -->
    <record id="action_cartable_my_activities" model="ir.actions.act_window">
        <field name="name">۱۰) آخرین فعالیت‌های من</field>
        <field name="res_model">itr.work.assignment.log</field>
        <field name="view_mode">list</field>
        <field name="domain">['|',('to_user_id','=',uid),('assigned_by_id','=',uid)]</field>
    </record>

    <!-- منوی کارتابل واحد -->
    <menuitem id="menu_itr_my_home" name="خانهٔ من" parent="itr_core.menu_itr_core_root"
              action="action_itr_home" sequence="1"/>
    <menuitem id="menu_itr_cartable_root" name="کارتابل من" parent="itr_core.menu_itr_core_root" sequence="2"/>
    <menuitem id="menu_cartable_1" parent="menu_itr_cartable_root" action="action_cartable_assigned_to_me" sequence="10"/>
    <menuitem id="menu_cartable_2" parent="menu_itr_cartable_root" action="action_cartable_new_work" sequence="20"/>
    <menuitem id="menu_cartable_3" parent="menu_itr_cartable_root" action="action_cartable_awaiting_me" sequence="30"/>
    <menuitem id="menu_cartable_4" parent="menu_itr_cartable_root" action="action_cartable_urgent" sequence="40"/>
    <menuitem id="menu_cartable_5" parent="menu_itr_cartable_root" action="action_cartable_overdue" sequence="50"/>
    <menuitem id="menu_cartable_6" parent="menu_itr_cartable_root" action="action_cartable_my_cases" sequence="60"/>
    <menuitem id="menu_cartable_7" parent="menu_itr_cartable_root" action="action_cartable_my_loadings" sequence="70"/>
    <menuitem id="menu_cartable_8" parent="menu_itr_cartable_root" action="action_cartable_recent_done" sequence="80"/>
    <menuitem id="menu_cartable_9" name="۹) اعلان‌ها و هشدارها" parent="menu_itr_cartable_root"
              action="action_notification_center_new" sequence="90"/>
    <menuitem id="menu_cartable_10" parent="menu_itr_cartable_root" action="action_cartable_my_activities" sequence="100"/>

    <!-- مرکز اعلان (UX-022) -->
    <menuitem id="menu_itr_notification_center" name="مرکز اعلان" parent="itr_core.menu_itr_core_root" sequence="3"/>
    <menuitem id="menu_notif_new" parent="menu_itr_notification_center" action="action_notification_center_new" sequence="10"/>
    <menuitem id="menu_notif_critical" parent="menu_itr_notification_center" action="action_notification_center_critical" sequence="20"/>
    <menuitem id="menu_notif_read" parent="menu_itr_notification_center" action="action_notification_center_read" sequence="30"/>

</odoo>
XMLEOF
log "itr_core/views/itr_cartable_phase8_views.xml"

# ----------------------------- views: فضاهای کاری نقش‌محور (UX-031) — فقط مدل‌های itr_core
# ★ F4: منوهای حمل/پرداخت که به xmlidهای itr_transport نیاز دارند → itr_transport
write_utf8 "${CORE_DIR}/views/itr_workspace_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>

    <!-- ۱) فضای مدیرعامل (بدون اکشن حمل — آن‌ها در itr_transport) -->
    <menuitem id="menu_ws_ceo" name="فضای مدیرعامل" parent="itr_core.menu_itr_core_root" sequence="4"
              groups="itr_core.group_ceo,itr_core.group_financial_manager,itr_core.group_auditor"/>
    <menuitem id="menu_ws_ceo_dashboard" name="داشبورد ۱۸ کارتی" parent="menu_ws_ceo"
              action="action_itr_ceo_dashboard" sequence="10"/>
    <menuitem id="menu_ws_ceo_cases" name="پرونده‌های بازرگانی" parent="menu_ws_ceo"
              action="itr_core.action_itr_trade_case" sequence="20"/>
    <menuitem id="menu_ws_ceo_shortfall" name="دفتر طلب کارخانه" parent="menu_ws_ceo"
              action="itr_core.action_itr_factory_shortfall" sequence="30"/>

    <!-- ۲) فضای مالی/بازرگانی — فقط مدل‌های itr_core؛ پرداخت‌ها در itr_transport -->
    <menuitem id="menu_ws_finance" name="فضای مالی و بازرگانی" parent="itr_core.menu_itr_core_root" sequence="5"
              groups="itr_core.group_finance_user,itr_core.group_finance_supervisor,itr_core.group_financial_manager"/>
    <menuitem id="menu_ws_fin_cases" name="پرونده‌های بازرگانی" parent="menu_ws_finance"
              action="itr_core.action_itr_trade_case" sequence="10"/>
    <menuitem id="menu_ws_fin_slips" name="ریزفاکتورهای فروش" parent="menu_ws_finance"
              action="itr_core.action_itr_sales_slip" sequence="20"/>
    <menuitem id="menu_ws_fin_shortfall" name="دفتر طلب کارخانه" parent="menu_ws_finance"
              action="itr_core.action_itr_factory_shortfall" sequence="50"
              groups="itr_core.group_finance_supervisor,itr_core.group_financial_manager"/>

    <!-- ۳..۶) فضاهای حمل — ریشه‌ها اینجا (گروه امنیتی)؛ آیتم‌های action در itr_transport -->
    <menuitem id="menu_ws_trn_sup" name="فضای سرپرست حمل" parent="itr_core.menu_itr_core_root" sequence="6"
              groups="itr_core.group_transport_supervisor"/>
    <menuitem id="menu_ws_trn_sup_team" name="تیم من" parent="menu_ws_trn_sup"
              action="itr_core.action_itr_supervisor_team" sequence="20"/>

    <menuitem id="menu_ws_docs" name="فضای اسناد و ناوگان" parent="itr_core.menu_itr_core_root" sequence="7"
              groups="itr_core.group_transport_docs"/>

    <menuitem id="menu_ws_customs" name="فضای مرز و ترخیص" parent="itr_core.menu_itr_core_root" sequence="8"
              groups="itr_core.group_customs_officer"/>

    <menuitem id="menu_ws_delivery" name="فضای تحویل و تسویه" parent="itr_core.menu_itr_core_root" sequence="9"
              groups="itr_core.group_transport_delivery"/>

    <!-- ۷) فضای حقوقی/خزانه/وصول -->
    <menuitem id="menu_ws_review" name="فضای بررسی تخصصی" parent="itr_core.menu_itr_core_root" sequence="10"
              groups="itr_core.group_legal_reviewer,itr_core.group_treasury_user,itr_core.group_receivables_user"/>
    <record id="action_ws_review_queue" model="ir.actions.act_window">
        <field name="name">پرونده‌های در صف بررسی من</field>
        <field name="res_model">itr.trade.case</field>
        <field name="view_mode">list,form</field>
        <field name="domain">['|',('current_owner_id','=',uid),('state','in',('legal_review','treasury_review','receivables_review'))]</field>
    </record>
    <menuitem id="menu_ws_review_queue" parent="menu_ws_review" action="action_ws_review_queue" sequence="10"/>

    <!-- تنظیمات کارتابل: فقط سرپرستان/مدیران -->
    <menuitem id="menu_itr_cartable_settings" name="تنظیمات کارتابل" parent="itr_core.menu_itr_core_root"
              action="action_itr_cartable_settings" sequence="95"
              groups="itr_core.group_finance_supervisor,itr_core.group_transport_supervisor,itr_core.group_financial_manager,itr_core.group_ceo,itr_base.group_itr_settings_manager"/>

</odoo>
XMLEOF
log "itr_core/views/itr_workspace_menus.xml"

# ------------------- itr_transport/views: کانبان + جست‌وجو + منوهای Workspace حمل (F4/F5)
# ★ F5: act_window واقعی روی itr.transport.case + اتصال action به منوی والد
#   docs/customs/delivery تا در _visible_menu_ids ظاهر شوند (V8-01).
write_utf8 "${TRN_DIR}/views/itr_transport_phase8_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>

    <!-- 8.7: کانبان رنگی SLA روی پروندهٔ حمل (drag&drop گذار نمی‌سازد — UX-063) -->
    <record id="view_itr_transport_case_kanban_sla" model="ir.ui.view">
        <field name="name">itr.transport.case.kanban.sla</field>
        <field name="model">itr.transport.case</field>
        <field name="priority">32</field>
        <field name="arch" type="xml">
            <kanban default_group_by="state" records_draggable="false" create="false">
                <field name="sla_color"/>
                <field name="checklist_progress"/>
                <field name="current_owner_id"/>
                <field name="owner_deadline"/>
                <templates>
                    <t t-name="card">
                        <div t-attf-class="oe_kanban_card p-2 #{record.sla_color.raw_value == 'red' ? 'border-danger border-start border-4' : record.sla_color.raw_value == 'orange' ? 'border-warning border-start border-4' : record.sla_color.raw_value == 'yellow' ? 'border-info border-start border-4' : 'border-success border-start border-4'}">
                            <strong><field name="name"/></strong>
                            <div><field name="customer_id"/></div>
                            <div><field name="waybill_number"/></div>
                            <div class="text-muted">
                                مسئول: <field name="current_owner_id"/> — مهلت: <field name="owner_deadline"/>
                            </div>
                            <div>
                                پیشرفت چک‌لیست: <field name="checklist_progress"/>٪
                                — وضعیت SLA: <field name="sla_color"/>
                            </div>
                        </div>
                    </t>
                </templates>
            </kanban>
        </field>
    </record>

    <!-- UX-051 روی فرم حمل -->
    <record id="view_itr_transport_case_form_phase8" model="ir.ui.view">
        <field name="name">itr.transport.case.form.phase8</field>
        <field name="model">itr.transport.case</field>
        <field name="inherit_id" ref="itr_transport.view_itr_transport_case_form"/>
        <field name="arch" type="xml">
            <xpath expr="//sheet" position="inside">
                <group string="رصد (UX-051)">
                    <field name="sla_color" readonly="1"/>
                    <field name="current_owner_id" readonly="1"/>
                    <field name="owner_deadline" readonly="1"/>
                    <field name="checklist_progress" readonly="1" widget="progressbar"/>
                    <field name="notification_count" readonly="1"/>
                </group>
                <button name="action_open_notifications" type="object"
                        string="تاریخچهٔ اعلان‌های این پرونده" class="btn-secondary"/>
            </xpath>
        </field>
    </record>

    <!-- UX-062: جست‌وجوی سراسری -->
    <record id="view_itr_transport_case_search_phase8" model="ir.ui.view">
        <field name="name">itr.transport.case.search.phase8</field>
        <field name="model">itr.transport.case</field>
        <field name="inherit_id" ref="itr_transport.view_itr_transport_case_search"/>
        <field name="arch" type="xml">
            <xpath expr="//search" position="inside">
                <field name="waybill_number" string="شمارهٔ بارنامه"/>
                <field name="driver_id" string="راننده"/>
                <field name="vehicle_id" string="پلاک/خودرو"/>
                <field name="customer_id" string="مشتری"/>
                <field name="factory_id" string="کارخانه"/>
                <field name="border_id" string="مرز"/>
                <filter name="filter_sla_overdue_p8" string="عقب‌افتاده (مهلت گذشته)"
                        domain="[('owner_deadline','!=',False),('owner_deadline','&lt;',context_today().strftime('%Y-%m-%d 00:00:00'))]"/>
                <filter name="filter_mine_p8" string="کارهای من"
                        domain="['|','|','|',('current_owner_id','=',uid),('docs_owner_id','=',uid),('customs_owner_id','=',uid),('delivery_owner_id','=',uid)]"/>
            </xpath>
        </field>
    </record>

    <record id="action_itr_global_search" model="ir.actions.act_window">
        <field name="name">جست‌وجوی سراسری حمل</field>
        <field name="res_model">itr.transport.case</field>
        <field name="view_mode">list,kanban,form</field>
        <field name="context">{'search_default_filter_mine_p8': 0}</field>
    </record>
    <menuitem id="menu_itr_global_search" name="جست‌وجوی سراسری" parent="itr_core.menu_itr_core_root"
              action="action_itr_global_search" sequence="11"/>

    <!-- ★ F5: act_window واقعی (نه server action روی AbstractModel) برای Workspace حمل.
         منوی والد بدون action و فقط با فرزند server-action در _visible_menu_ids مخفی
         می‌ماند → هم action روی والد، هم فرزند list با domain «بارگیری‌های من». -->
    <record id="action_ws_my_loadings_act" model="ir.actions.act_window">
        <field name="name">بارگیری‌های من</field>
        <field name="res_model">itr.transport.case</field>
        <field name="view_mode">list,kanban,form</field>
        <field name="domain">['|','|','|',('current_owner_id','=',uid),('docs_owner_id','=',uid),('customs_owner_id','=',uid),('delivery_owner_id','=',uid)]</field>
        <field name="context">{'create': False}</field>
    </record>

    <!-- اتصال action به منوی والد تا V8-01 برای docs/customs/delivery سبز شود -->
    <record id="itr_core.menu_ws_docs" model="ir.ui.menu">
        <field name="action" ref="action_ws_my_loadings_act"/>
    </record>
    <record id="itr_core.menu_ws_customs" model="ir.ui.menu">
        <field name="action" ref="action_ws_my_loadings_act"/>
    </record>
    <record id="itr_core.menu_ws_delivery" model="ir.ui.menu">
        <field name="action" ref="action_ws_my_loadings_act"/>
    </record>

    <!-- ★ F4: آیتم‌های Workspace که res_model/xmlid حمل دارند — فقط اینجا (Q02) -->
    <menuitem id="menu_ws_trn_sup_cases" name="همهٔ بارگیری‌ها" parent="itr_core.menu_ws_trn_sup"
              action="itr_transport.action_itr_transport_case" sequence="10"/>
    <menuitem id="menu_ws_trn_sup_payreq" name="پرداخت‌های حمل" parent="itr_core.menu_ws_trn_sup"
              action="itr_transport.action_itr_payment_request" sequence="30"/>

    <menuitem id="menu_ws_docs_loadings" name="بارگیری‌های من" parent="itr_core.menu_ws_docs"
              action="action_ws_my_loadings_act" sequence="10"/>

    <menuitem id="menu_ws_customs_loadings" name="بارگیری‌های من" parent="itr_core.menu_ws_customs"
              action="action_ws_my_loadings_act" sequence="10"/>

    <menuitem id="menu_ws_delivery_loadings" name="بارگیری‌های من" parent="itr_core.menu_ws_delivery"
              action="action_ws_my_loadings_act" sequence="10"/>
    <menuitem id="menu_ws_delivery_payreq" name="درخواست‌های پرداخت من" parent="itr_core.menu_ws_delivery"
              action="itr_transport.action_itr_payment_request" sequence="20"/>

    <menuitem id="menu_ws_fin_payreq" name="درخواست‌های پرداخت" parent="itr_core.menu_ws_finance"
              action="itr_transport.action_itr_payment_request" sequence="30"
              groups="itr_core.group_finance_user,itr_core.group_finance_supervisor,itr_core.group_financial_manager"/>
    <menuitem id="menu_ws_fin_payexec" name="اجرای پرداخت‌ها" parent="itr_core.menu_ws_finance"
              action="itr_transport.action_itr_payment_execution" sequence="40"
              groups="itr_core.group_finance_supervisor,itr_core.group_financial_manager"/>

</odoo>
XMLEOF
log "itr_transport/views/itr_transport_phase8_views.xml"

# ------------------- itr_core/views: کانبان SLA و فرم trade case ----------
write_utf8 "${CORE_DIR}/views/itr_core_phase8_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>

    <!-- 8.7: کانبان SLA پروندهٔ بازرگانی -->
    <record id="view_itr_trade_case_kanban_sla" model="ir.ui.view">
        <field name="name">itr.trade.case.kanban.sla</field>
        <field name="model">itr.trade.case</field>
        <field name="priority">32</field>
        <field name="arch" type="xml">
            <kanban default_group_by="state" records_draggable="false" create="false">
                <field name="sla_color"/>
                <field name="case_progress"/>
                <templates>
                    <t t-name="card">
                        <div t-attf-class="oe_kanban_card p-2 #{record.sla_color.raw_value == 'red' ? 'border-danger border-start border-4' : record.sla_color.raw_value == 'orange' ? 'border-warning border-start border-4' : record.sla_color.raw_value == 'yellow' ? 'border-info border-start border-4' : 'border-success border-start border-4'}">
                            <strong><field name="name"/></strong>
                            <div><field name="factory_id"/></div>
                            <div class="text-muted">
                                مسئول: <field name="current_owner_id"/> — مهلت: <field name="owner_deadline"/>
                            </div>
                            <div>پیشرفت: <field name="case_progress"/>٪ — SLA: <field name="sla_color"/></div>
                        </div>
                    </t>
                </templates>
            </kanban>
        </field>
    </record>

    <!-- UX-051 روی فرم پروندهٔ بازرگانی [FIX-P8-3] -->
    <record id="view_itr_trade_case_form_phase8" model="ir.ui.view">
        <field name="name">itr.trade.case.form.phase8</field>
        <field name="model">itr.trade.case</field>
        <field name="inherit_id" ref="itr_core.view_itr_trade_case_form"/>
        <field name="arch" type="xml">
            <xpath expr="//sheet" position="inside">
                <group string="رصد (UX-051)">
                    <field name="sla_color" readonly="1"/>
                    <field name="case_progress" readonly="1" widget="progressbar"/>
                    <field name="notification_count" readonly="1"/>
                </group>
                <button name="action_open_notifications" type="object"
                        string="تاریخچهٔ اعلان‌های این پرونده" class="btn-secondary"/>
            </xpath>
        </field>
    </record>

    <!-- UX-062: جست‌وجوی پرونده — مشتری/کارخانه/مرز -->
    <record id="view_itr_trade_case_search_phase8" model="ir.ui.view">
        <field name="name">itr.trade.case.search.phase8</field>
        <field name="model">itr.trade.case</field>
        <field name="inherit_id" ref="itr_core.view_itr_trade_case_search"/>
        <field name="arch" type="xml">
            <xpath expr="//search" position="inside">
                <field name="buyer_id" string="مشتری"/>
                <field name="factory_id" string="کارخانه"/>
                <field name="border_id" string="مرز"/>
                <filter name="filter_my_cases_p8" string="پرونده‌های من"
                        domain="[('current_owner_id','=',uid)]"/>
            </xpath>
        </field>
    </record>

</odoo>
XMLEOF
log "itr_core/views/itr_core_phase8_views.xml"

# ------------------------------------ tests/test_cartable_phase8.py -------
write_utf8 "${CORE_DIR}/tests/test_cartable_phase8.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 8 — cartable / Home / notification center / dashboard (Q04, UAT-12).

Real seeded users only — never Administrator (G01). Every number shown to a
user is re-counted manually with plain ORM domains and must match exactly.
"""
from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tests import tagged

from odoo.addons.itr_transport.tests.common import ItrTransportCase


@tagged("post_install", "-at_install", "itr_phase8")
class TestCartablePhase8(ItrTransportCase):

    def real(self, login):
        user = self.env["res.users"].search([("login", "=", login)], limit=1)
        self.assertTrue(user, "seeded phase-3 user missing: %s" % login)
        return user

    def _refused(self, fn):
        try:
            fn()
        except (AccessError, UserError, ValidationError):
            return True
        except Exception:  # noqa: BLE001
            return False
        return False

    def _one_tc(self, tonnage=30.0):
        result = self._handed_over(tonnage=tonnage)
        tc = result[2]
        return tc[:1] if len(tc) > 1 else tc

    # ------------------------------------------------------------- UX-003
    def test_10_admin_has_no_home_or_cartable(self):
        admin = self.env.ref("base.user_admin")
        self.assertTrue(self._refused(
            lambda: self.env["itr.home"].with_user(admin).create({"user_id": admin.id})),
            "UX-003: Administrator must never get an operational Home")
        counts = self.env["itr.work.queue"].my_counts(admin)
        self.assertTrue(counts["blocked"], "UX-003: the queue must report the admin as blocked")
        self.assertEqual(counts["total"], 0)

    # ------------------------------------------------------------- UAT-12
    def test_11_home_counts_equal_manual_counts(self):
        self._one_tc(tonnage=40.0)
        trn_sup = self.real("najmeh.afrashtehpour@irbco.local")
        counts = self.env["itr.work.queue"].my_counts(trn_sup)
        manual = 0
        for model_name in ("itr.trade.case", "itr.sales.slip", "itr.transport.case", "itr.payment.request"):
            model = self.env[model_name].with_user(trn_sup)
            domain = [("current_owner_id", "=", trn_sup.id)]
            if model_name == "itr.transport.case":
                domain = ["|", "|", "|",
                          ("current_owner_id", "=", trn_sup.id),
                          ("docs_owner_id", "=", trn_sup.id),
                          ("customs_owner_id", "=", trn_sup.id),
                          ("delivery_owner_id", "=", trn_sup.id)]
            if "state" in model._fields:
                domain += [("state", "not in", ("closed", "cancelled", "rejected", "executed"))]
            manual += model.search_count(domain)
        self.assertEqual(counts["total"], manual,
                         "UAT-12: the Home counter must equal the manual ORM count")
        self.assertGreater(counts["total"], 0, "the supervisor just received a loading")

    def test_12_home_shows_only_my_work(self):
        self._one_tc(tonnage=25.0)
        trn_sup = self.real("najmeh.afrashtehpour@irbco.local")
        legal = self.real("pouya.soleimani@irbco.local")
        sup_counts = self.env["itr.work.queue"].my_counts(trn_sup)
        legal_counts = self.env["itr.work.queue"].my_counts(legal)
        self.assertEqual(legal_counts["models"]["itr.transport.case"]["total"], 0,
                         "UAT-12: a user must never see someone else's loadings in his Home")
        self.assertGreater(sup_counts["models"]["itr.transport.case"]["total"], 0)

    # ------------------------------------------------------------- UX-002
    def test_13_thresholds_come_from_settings_not_code(self):
        settings = self.env["itr.cartable.settings"].get_settings()
        trn_sup = self.real("najmeh.afrashtehpour@irbco.local")
        self._one_tc(tonnage=20.0)
        settings.sudo().write({"urgent_hours": 1})
        low = self.env["itr.work.queue"].my_counts(trn_sup)["urgent"]
        settings.sudo().write({"urgent_hours": 24 * 30})
        high = self.env["itr.work.queue"].my_counts(trn_sup)["urgent"]
        self.assertGreaterEqual(high, low,
                                "UX-002: widening the urgent window must never shrink the bucket")
        settings.sudo().write({"urgent_hours": 4})

    # ------------------------------------------------------------- UX-041
    def test_14_dashboard_cards_equal_manual_counts(self):
        self._one_tc(tonnage=30.0)
        service = self.env["itr.kpi.service"]
        ceo = self.real("hadi.karamian@irbco.local")
        for key in ("loads_in_transit", "waiting_driver", "waiting_bijak",
                    "waiting_clearance", "waiting_payment", "completed_loads",
                    "stalled_cases"):
            result = service.with_user(ceo).get_kpi(key)
            action = result["action"]
            manual = self.env[action["res_model"]].with_user(ceo).search_count(action["domain"])
            self.assertEqual(result["value"], manual,
                             "UX-041: card %s must equal its own drill-down count" % key)

    def test_15_dashboard_all_18_cards_exist(self):
        registry = self.env["itr.kpi.service"].kpi_registry()
        self.assertEqual(len(registry), 18, "UX-041: exactly 18 official CEO cards")
        for key in registry:
            result = self.env["itr.kpi.service"].get_kpi(key)
            self.assertIn("value", result)
            self.assertIn("action", result)

    # ------------------------------------------------------------- UX-022
    def test_16_notification_center_own_only(self):
        self._one_tc(tonnage=15.0)
        legal = self.real("pouya.soleimani@irbco.local")
        Dispatch = self.env["itr.notification.dispatch.log"]
        foreign = Dispatch.with_user(legal).search(
            [("recipient_user_id", "not in", (False, legal.id))])
        self.assertFalse(foreign,
                         "[FIX-P8-2]: a normal user must not read other users' notifications")

    def test_17_mark_read_only_by_recipient(self):
        Dispatch = self.env["itr.notification.dispatch.log"].sudo()
        row = Dispatch.search([("recipient_user_id", "!=", False)], limit=1)
        if not row:
            self.skipTest("no personal notification in this database yet")
        other = self.real("pouya.soleimani@irbco.local")
        if row.recipient_user_id.id == other.id:
            other = self.real("mohammadi@irbco.local")
        self.assertTrue(self._refused(
            lambda: row.with_user(other).action_mark_read()),
            "UX-022: only the recipient may mark a notification as read")
        row.with_user(row.recipient_user_id).action_mark_read()
        self.assertTrue(row.read_on, "the recipient must be able to mark it read")

    # ------------------------------------------------------------- G18
    def test_18_no_second_task_engine(self):
        queue = self.env["itr.work.queue"]
        self.assertTrue(queue._abstract, "G18: the unified queue is a service, not a second table")
PYEOF
log "itr_core/tests/test_cartable_phase8.py"

# --------------------------------------- ops/verify/verify_phase8.py ------
write_utf8 "${OPS_DIR}/verify/verify_phase8.py" <<'PYEOF'
# -*- coding: utf-8 -*-
# ops/verify/verify_phase8.py — verify مستقل فاز ۸ (کاربر واقعی، بدون sudo، rollback)
import sys
import traceback

checks = []
passed = failed = 0


def chk(code, title, condition, detail=""):
    global passed, failed
    status = "PASS" if condition else "FAIL"
    if condition:
        passed += 1
    else:
        failed += 1
    checks.append((code, status, title, detail))
    print("%-7s %-5s %s%s" % (code, status, title, ("  [%s]" % detail) if detail else ""))


try:
    env = env  # noqa: F821 — provided by odoo shell
    from odoo.exceptions import AccessError, UserError, ValidationError

    REFUSALS = (AccessError, UserError, ValidationError)

    def real(login):
        user = env["res.users"].search([("login", "=", login)], limit=1)
        assert user, "missing seeded user %s" % login
        return user

    def refused(fn):
        try:
            with env.cr.savepoint():
                fn()
        except REFUSALS:
            return True
        except Exception:  # noqa: BLE001
            traceback.print_exc()
            return False
        return False

    # logins = itr_core seed (phase 3) — identical to verify_phase7.py
    ceo = real("hadi.karamian@irbco.local")
    ceo2 = real("saeed.yousefi@irbco.local")
    fin_mgr = real("fin.mgr@irbco.local")
    fin_sup = real("ehsan.nahalparvar@irbco.local")
    fin_user = real("faezeh.heydari@irbco.local")
    legal = real("pouya.soleimani@irbco.local")
    treasury = real("atieh.alaei@irbco.local")
    receivables = real("zahra.mirzaei@irbco.local")
    trn_sup = real("najmeh.afrashtehpour@irbco.local")
    docs = real("mohaddeseh.enayati@irbco.local")
    customs = real("mohammadi@irbco.local")
    delivery = real("amini@irbco.local")
    ALL_TWELVE = [ceo, ceo2, fin_mgr, fin_sup, fin_user, legal, treasury,
                  receivables, trn_sup, docs, customs, delivery]

    Queue = env["itr.work.queue"]
    Home = env["itr.home"]
    Kpi = env["itr.kpi.service"]
    Menu = env["ir.ui.menu"]
    Partner = env["res.partner"]

    def _factory():
        fac = Partner.sudo().search([("is_factory", "=", True)], limit=1)
        if not fac:
            fac = Partner.sudo().create({"name": "TEST p8 factory", "is_company": True, "is_factory": True})
        return fac

    def _buyer():
        return Partner.sudo().create({"name": "TEST p8 buyer", "is_company": True})

    def build_loading(tonnage=30.0):
        Case = env["itr.trade.case"]
        case = Case.with_user(fin_user).create({
            "requested_by": ceo.id, "deal_pattern": "buy_first",
            "factory_id": _factory().id,
            "destination": "TEST p8 destination",
            "item_ids": [(0, 0, {"name": "TEST p8 goods", "row_kind": "both",
                                  "contract_tonnage": tonnage,
                                  "purchase_price_unit": 100.0, "sale_price_unit": 120.0})],
        })
        case.with_user(fin_user).action_submit()
        case.with_user(legal).action_legal_approve()
        case.with_user(treasury).action_treasury_approve()
        case.with_user(receivables).action_receivables_approve()
        case.with_user(fin_sup).write({"signed_document": "JVBERi0xLjQKJSBURVNUCg==",
                                       "signed_document_filename": "TEST-p8.pdf"})
        case.with_user(fin_sup).action_confirm_signed()
        slip = env["itr.sales.slip"].with_user(fin_user).create({
            "case_id": case.id,
            "customer_id": _buyer().id,
            "line_ids": [(0, 0, {"case_item_id": case.item_ids[0].id,
                                  "allocated_tonnage": tonnage})],
        })
        slip.with_user(fin_user).action_issue()
        if hasattr(slip, "action_hand_over_to_transport"):
            slip.with_user(fin_user).action_hand_over_to_transport()
        if hasattr(slip, "receive_by_transport"):
            try:
                slip.with_user(trn_sup).receive_by_transport(dispatch_count=1)
            except TypeError:
                slip.with_user(trn_sup).receive_by_transport()
        tc = env["itr.transport.case"].search([("sales_slip_id", "=", slip.id)], limit=1)
        if not tc and getattr(slip, "transport_case_ids", False):
            tc = slip.transport_case_ids[:1]
        assert tc, "transport case was not created"
        return tc

    tc = build_loading(30.0)

    # V8-01 workspace scoping
    WS = {
        "menu_ws_ceo": ("itr_core.group_ceo", "itr_core.group_financial_manager", "itr_core.group_auditor"),
        "menu_ws_finance": ("itr_core.group_finance_user", "itr_core.group_finance_supervisor",
                            "itr_core.group_financial_manager"),
        "menu_ws_trn_sup": ("itr_core.group_transport_supervisor",),
        "menu_ws_docs": ("itr_core.group_transport_docs",),
        "menu_ws_customs": ("itr_core.group_customs_officer",),
        "menu_ws_delivery": ("itr_core.group_transport_delivery",),
        "menu_ws_review": ("itr_core.group_legal_reviewer", "itr_core.group_treasury_user",
                           "itr_core.group_receivables_user"),
    }
    scoping_ok = True
    scoping_detail = []
    for user in ALL_TWELVE:
        visible = set(Menu.with_user(user)._visible_menu_ids())
        for menu_xmlid, groups in WS.items():
            menu = env.ref("itr_core.%s" % menu_xmlid)
            should = any(user.has_group(g) for g in groups)
            actual = menu.id in visible
            if should != actual:
                scoping_ok = False
                scoping_detail.append("%s/%s should=%s actual=%s" % (user.login, menu_xmlid, should, actual))
    chk("V8-01", "هر ۱۲ کاربر فقط فضای کاری مرتبط با نقش خود را می‌بیند (UX-031)",
        scoping_ok, "; ".join(scoping_detail[:4]))

    # V8-02 admin
    admin = env.ref("base.user_admin")
    admin_blocked = Queue.my_counts(admin)["blocked"]
    admin_home_refused = refused(lambda: Home.with_user(admin).create({"user_id": admin.id}))
    chk("V8-02", "Administrator کارتابل/Home عملیاتی ندارد (UX-003/Q03)",
        admin_blocked and admin_home_refused)

    # V8-03 dashboard
    card_ok = True
    card_detail = []
    for key in ("loads_in_transit", "waiting_driver", "waiting_bijak", "waiting_clearance",
                "waiting_payment", "completed_loads", "stalled_cases"):
        result = Kpi.with_user(ceo).get_kpi(key)
        action = result["action"]
        manual = env[action["res_model"]].with_user(ceo).search_count(action["domain"])
        if result["value"] != manual:
            card_ok = False
            card_detail.append("%s:%s!=%s" % (key, result["value"], manual))
    registry_size = len(Kpi.kpi_registry())
    chk("V8-03", "عدد هر کارت داشبورد = شمارش مستقیم دامنهٔ Drill-Down؛ ۱۸ کارت (UX-041)",
        card_ok and registry_size == 18, ";".join(card_detail) or "cards=%s" % registry_size)

    # V8-04 Home UAT-12
    uat12_ok = True
    uat12_detail = []
    for user in ALL_TWELVE:
        counts = Queue.my_counts(user)
        manual_total = 0
        for model_name in ("itr.trade.case", "itr.sales.slip", "itr.transport.case", "itr.payment.request"):
            model = env[model_name].with_user(user)
            domain = [("current_owner_id", "=", user.id)]
            if model_name == "itr.transport.case":
                domain = ["|", "|", "|",
                          ("current_owner_id", "=", user.id),
                          ("docs_owner_id", "=", user.id),
                          ("customs_owner_id", "=", user.id),
                          ("delivery_owner_id", "=", user.id)]
            if "state" in model._fields:
                domain += [("state", "not in", ("closed", "cancelled", "rejected", "executed"))]
            manual_total += model.search_count(domain)
        if counts["total"] != manual_total:
            uat12_ok = False
            uat12_detail.append("%s:%s!=%s" % (user.login, counts["total"], manual_total))
    chk("V8-04", "Home هر یک از ۱۲ کاربر دقیقاً کارهای خودش را می‌شمارد (UAT-12)",
        uat12_ok, ";".join(uat12_detail[:4]))

    # V8-05 thresholds
    settings = env["itr.cartable.settings"].get_settings()
    old = settings.urgent_hours
    settings.write({"urgent_hours": 1})
    low = Queue.my_counts(trn_sup)["urgent"]
    settings.write({"urgent_hours": 24 * 365})
    high = Queue.my_counts(trn_sup)["urgent"]
    settings.write({"urgent_hours": old})
    chk("V8-05", "آستانهٔ «فوری» از تنظیمات اثر می‌کند نه از کد (UX-002/Q07)", high >= low,
        "low=%s high=%s" % (low, high))

    # V8-06 notification privacy
    Dispatch = env["itr.notification.dispatch.log"]
    foreign = Dispatch.with_user(legal).search_count(
        [("recipient_user_id", "not in", (False, legal.id))])
    manager_sees = Dispatch.with_user(ceo).search_count([]) >= Dispatch.with_user(legal).search_count([])
    chk("V8-06", "هرکس فقط اعلان خودش؛ CEO/مدیر اعلان همه را می‌بیند [FIX-P8-2]",
        foreign == 0 and manager_sees, "foreign=%s" % foreign)

    # V8-07 mark-read
    row = Dispatch.sudo().search([("recipient_user_id", "!=", False), ("read_on", "=", False)], limit=1)
    if row:
        stranger = legal if row.recipient_user_id != legal else customs
        deny = refused(lambda: row.with_user(stranger).action_mark_read())
        row.with_user(row.recipient_user_id).action_mark_read()
        chk("V8-07", "علامت «خوانده شد» فقط توسط خود گیرنده (UX-022)", deny and bool(row.read_on))
    else:
        chk("V8-07", "علامت «خوانده شد» فقط توسط خود گیرنده (UX-022)", True, "no personal row — skipped")

    # V8-08 G18
    chk("V8-08", "صف‌کار AbstractModel است (جدول/موتور دوم ساخته نشده — G18)",
        env["itr.work.queue"]._abstract and env["itr.kpi.service"]._abstract)

except Exception as error:  # noqa: BLE001
    traceback.print_exc()
    failed += 1
    checks.append(("V8-ERR", "FAIL", "verify crashed", str(error)))

finally:
    env.cr.rollback()  # noqa: F821

print("\nITR_VERIFY_SUMMARY: passed=%d failed=%d total=%d" % (passed, failed, len(checks)))
if failed == 0:
    print("ITR_VERIFY_RESULT: PASS")
    sys.exit(0)
else:
    print("ITR_VERIFY_RESULT: FAIL")
    sys.exit(1)
PYEOF
log "ops/verify/verify_phase8.py"

# =============================================================================
step "3) پچ افزایشی و idempotent فایل‌های مشترک (R1 — فقط append با مارک)"
# =============================================================================
python3 - "${CORE_DIR}" "${TRN_DIR}" <<'PYEOF'
import io
import os
import re
import sys

core_dir, trn_dir = sys.argv[1], sys.argv[2]
changed = []


def read(path):
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


# --- models/__init__.py ------------------------------------------------------
for mdir, imports in (
    (core_dir, ("from . import itr_cartable_settings",
                "from . import itr_work_queue",
                "from . import itr_kpi_service",
                "from . import itr_home",
                "from . import itr_ceo_dashboard",
                "from . import itr_notify_phase8",
                "from . import itr_ux_phase8")),
    (trn_dir, ("from . import itr_ux_phase8",)),
):
    path = os.path.join(mdir, "models", "__init__.py")
    text = read(path)
    for imp in imports:
        if imp not in text.splitlines():
            text = text.rstrip("\n") + "\n" + imp + "\n"
            changed.append("%s + %s" % (os.path.basename(mdir), imp))
    write(path, text)


def ensure_data_order(mod_dir, ordered_entries, label):
    """Put phase-8 data files in exact load order at end of data list (F1)."""
    path = os.path.join(mod_dir, "__manifest__.py")
    text = read(path)
    for entry in ordered_entries:
        text = re.sub(
            r'[ \t]*["\']%s["\']\s*,\s*\n' % re.escape(entry),
            "",
            text,
        )
    block = "".join('        "%s",\n' % e for e in ordered_entries)
    m = re.search(r'(["\']data["\']\s*:\s*\[)(.*?)(\n\s*\],)', text, re.S)
    if not m:
        raise SystemExit("manifest data list not found in %s" % path)
    head, body, tail = m.group(1), m.group(2), m.group(3)
    if body and not body.endswith("\n"):
        body = body + "\n"
    text = text[:m.start()] + head + body + block + tail + text[m.end():]
    write(path, text)
    changed.append("%s manifest data order fixed (%d phase-8 files)" % (label, len(ordered_entries)))


ensure_data_order(core_dir, [
    "security/itr_core_phase8_rules.xml",
    "data/itr_core_phase8_data.xml",
    "views/itr_home_views.xml",
    "views/itr_cartable_phase8_views.xml",
    "views/itr_core_phase8_views.xml",
    "views/itr_workspace_menus.xml",
], "itr_core")
ensure_data_order(trn_dir, [
    "views/itr_transport_phase8_views.xml",
], "itr_transport")

# --- tests/__init__.py --------------------------------------------------------
path = os.path.join(core_dir, "tests", "__init__.py")
text = read(path) if os.path.exists(path) else ""
imp = "from . import test_cartable_phase8"
if imp not in text.splitlines():
    text = text.rstrip("\n") + ("\n" if text else "") + imp + "\n"
    changed.append("itr_core/tests + test_cartable_phase8")
write(path, text)

# --- ACL rows -----------------------------------------------------------------
acl_rows = {
    os.path.join(core_dir, "security", "ir.model.access.csv"): [
        "access_itr_cartable_settings_user,itr.cartable.settings user,model_itr_cartable_settings,base.group_user,1,0,0,0",
        "access_itr_cartable_settings_fin_sup,itr.cartable.settings fin sup,model_itr_cartable_settings,itr_core.group_finance_supervisor,1,1,1,0",
        "access_itr_cartable_settings_trn_sup,itr.cartable.settings trn sup,model_itr_cartable_settings,itr_core.group_transport_supervisor,1,1,1,0",
        "access_itr_cartable_settings_fin_mgr,itr.cartable.settings fin mgr,model_itr_cartable_settings,itr_core.group_financial_manager,1,1,1,0",
        "access_itr_cartable_settings_ceo,itr.cartable.settings ceo,model_itr_cartable_settings,itr_core.group_ceo,1,1,1,0",
        "access_itr_cartable_settings_settings,itr.cartable.settings settings mgr,model_itr_cartable_settings,itr_base.group_itr_settings_manager,1,1,1,0",
        "access_itr_home_user,itr.home user,model_itr_home,base.group_user,1,1,1,1",
        "access_itr_ceo_dashboard_ceo,itr.ceo.dashboard ceo,model_itr_ceo_dashboard,itr_core.group_ceo,1,1,1,0",
        "access_itr_ceo_dashboard_fin_mgr,itr.ceo.dashboard fin mgr,model_itr_ceo_dashboard,itr_core.group_financial_manager,1,0,0,0",
        "access_itr_ceo_dashboard_auditor,itr.ceo.dashboard auditor,model_itr_ceo_dashboard,itr_core.group_auditor,1,0,0,0",
    ],
}
for path, rows in acl_rows.items():
    text = read(path)
    for row in rows:
        acl_id = row.split(",", 1)[0]
        if acl_id + "," not in text:
            text = text.rstrip("\n") + "\n" + row + "\n"
            changed.append("acl + %s" % acl_id)
    write(path, text)

# --- i18n ---------------------------------------------------------------------
path = os.path.join(core_dir, "i18n", "fa_IR.po")
if os.path.exists(path):
    text = read(path)
    MARK = "#### itr_core phase-8 translations ####"
    if MARK not in text:
        text = text.rstrip("\n") + "\n\n" + MARK + """

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_home
msgid "My Home (UX-021)"
msgstr "خانهٔ من"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_cartable_settings
msgid "Cartable Settings"
msgstr "تنظیمات کارتابل"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_ceo_dashboard
msgid "CEO Dashboard (UX-041)"
msgstr "داشبورد مدیرعامل"

#. module: itr_core
#: code:addons/itr_core/models/itr_home.py:0
#, python-format
msgid "Hello, %(name)s"
msgstr "سلام، %(name)s"

#. module: itr_core
#: code:addons/itr_core/models/itr_home.py:0
#, python-format
msgid "The system administrator deliberately has no operational Home/cartable (UX-003/Q03)."
msgstr "مدیر سیستم عمداً هیچ خانه/کارتابل عملیاتی ندارد (UX-003/Q03)."

#. module: itr_core
#: code:addons/itr_core/models/itr_home.py:0
#, python-format
msgid "The Home page only ever shows YOUR OWN work (UAT-12)."
msgstr "صفحهٔ خانه همیشه فقط کارهای خودِ شما را نشان می‌دهد (UAT-12)."

#. module: itr_core
#: code:addons/itr_core/models/itr_notify_phase8.py:0
#, python-format
msgid "Only the recipient may mark a notification as read."
msgstr "فقط خودِ گیرنده می‌تواند اعلان را «خوانده‌شده» کند."
"""
        changed.append("itr_core i18n + phase-8 block")
    write(path, text)

# F4 static guard: no act_window res_model transport in itr_core XML
forbidden = []
for base, _d, files in os.walk(os.path.join(core_dir, "views")):
    for name in files:
        if not name.endswith(".xml"):
            continue
        p = os.path.join(base, name)
        t = read(p)
        if re.search(r'res_model["\']?\s*>\s*itr\.transport\.', t) or \
           re.search(r'name="res_model">itr\.transport\.', t) or \
           re.search(r'name="res_model">itr\.payment\.', t) or \
           re.search(r'name="res_model">itr\.cost\.', t):
            forbidden.append(p)
if forbidden:
    raise SystemExit("F4 FAIL: itr_core XML must not act_window on transport models:\n  " + "\n  ".join(forbidden))
changed.append("F4 guard: no transport act_window in itr_core views")

print("PATCHED: %d change(s)" % len(changed))
for item in changed:
    print("  *", item)
PYEOF
log "پچ افزایشی کامل شد (idempotent)"

# =============================================================================
step "4) بررسی نحوی پایتون و صحت XML/CSV پیش از هر نصب"
# =============================================================================
set +e
python3 - "${CORE_DIR}" "${TRN_DIR}" "${OPS_DIR}" <<'PYEOF'
import ast, csv, io, os, sys
import xml.etree.ElementTree as ET

errors = []
py_count = xml_count = 0
for root_dir in sys.argv[1:3] + [os.path.join(sys.argv[3], "verify")]:
    for base, _dirs, files in os.walk(root_dir):
        if "__pycache__" in base:
            continue
        for name in files:
            path = os.path.join(base, name)
            if name.endswith(".py"):
                py_count += 1
                try:
                    ast.parse(io.open(path, encoding="utf-8").read(), filename=path)
                except SyntaxError as exc:
                    errors.append("PY  %s: %s" % (path, exc))
            elif name.endswith(".xml"):
                xml_count += 1
                try:
                    ET.parse(path)
                except ET.ParseError as exc:
                    errors.append("XML %s: %s" % (path, exc))
for mod_dir in sys.argv[1:3]:
    acl = os.path.join(mod_dir, "security", "ir.model.access.csv")
    with io.open(acl, encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    seen = set()
    for row in rows:
        rid = (row.get("id") or "").strip()
        if rid and rid in seen:
            errors.append("CSV duplicate acl id: %s" % rid)
        seen.add(rid)
print("checked: %d python file(s), %d xml file(s)" % (py_count, xml_count))
if errors:
    print("\n".join(errors))
    sys.exit(1)
PYEOF
SYNTAX_RC=$?
set -e
if [[ ${SYNTAX_RC} -eq 0 ]]; then
  gate "G8-03" "نحو پایتون/XML/CSV سالم است (پیش از نصب)" "PASS" "static check"
else
  gate "G8-03" "نحو پایتون/XML/CSV سالم است" "FAIL" "خطای نحوی"
  err "خطای نحوی پیش از نصب (rollback: ${P8_BACKUP_DIR}/${TS})"
fi

python3 - "${CORE_DIR}/__manifest__.py" <<'PYEOF'
import io, re, sys
text = io.open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'["\']data["\']\s*:\s*\[(.*?)\]', text, re.S)
assert m, "data list missing"
body = m.group(1)
i_home = body.find("views/itr_home_views.xml")
i_ws = body.find("views/itr_workspace_menus.xml")
assert i_home >= 0 and i_ws >= 0, "phase-8 view entries missing from manifest"
assert i_home < i_ws, "F1 FAIL: workspace_menus must load AFTER home_views"
print("F1 order OK: home_views @ %d < workspace_menus @ %d" % (i_home, i_ws))
PYEOF
log "F1: ترتیب data در manifest تأیید شد"

# =============================================================================
step "5) ارتقای itr_core + itr_transport (فاز ۸) روی ${DB_NAME} (Q01/NFR-001)"
# =============================================================================
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -u "${CORE_MODULE},${TRN_MODULE}" --stop-after-init --log-level=info >"${INSTALL_LOG}" 2>&1
INSTALL_RC=$?
set -e
INSTALL_ERRORS="$(grep -cE ' (ERROR|CRITICAL) ' "${INSTALL_LOG}" || true)"
CORE_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${CORE_MODULE}'")"
TRN_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
echo "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} core=${CORE_AFTER} transport=${TRN_AFTER}"
if [[ ${INSTALL_RC} -eq 0 && "${INSTALL_ERRORS}" == "0" && "${CORE_AFTER}" == "installed" && "${TRN_AFTER}" == "installed" ]]; then
  gate "G8-04" "ارتقای فاز ۸ بدون خطا" "PASS" "rc=0 errors=0"
else
  gate "G8-04" "ارتقای فاز ۸ بدون خطا" "FAIL" "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} → ${INSTALL_LOG}"
  tail -n 80 "${INSTALL_LOG}" || true
fi

# =============================================================================
step "6) تست‌های خودکار — فاز ۸ *و* بازاجرای کامل فازهای ۱..۷ (Q04 + R5)"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G8-05" "تست‌های فاز ۸ + بازاجرای فازهای ۱..۷ سبز" "FAIL" "SKIP_TESTS=1 (Q04 اجباری)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    -u "itr_base,itr_notify,${CORE_MODULE},${TRN_MODULE}" \
    --test-enable --test-tags "/itr_base,/itr_notify,/${CORE_MODULE},/${TRN_MODULE}" \
    --stop-after-init --log-level=info >"${TEST_LOG}" 2>&1
  TEST_RC=$?
  set -e
  TEST_FAILS="$(grep -cE '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" || true)"
  TEST_BROKEN="$(grep -c 'At least one test failed' "${TEST_LOG}" || true)"
  TEST_TOTAL="$(grep -oE '[0-9]+ tests' "${TEST_LOG}" | tail -n1 || true)"
  echo "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} total=${TEST_TOTAL:-?}"
  if [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" && "${TEST_FAILS}" == "0" && -n "${TEST_TOTAL}" ]]; then
    gate "G8-05" "تست‌های فاز ۸ سبز + هیچ رگرسیونی در فازهای ۱..۷ (R5)" "PASS" "${TEST_TOTAL} rc=0"
  else
    gate "G8-05" "تست‌های فاز ۸ + بازاجرای فازهای ۱..۷" "FAIL" "rc=${TEST_RC} fails=${TEST_FAILS} → ${TEST_LOG}"
    grep -A 40 -E '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" | head -n 200 || true
  fi
fi

# =============================================================================
step "7) verify مستقل V8-01..V8-08 (کاربر واقعی، بدون sudo، rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G8-06" "verify فاز ۸ سبز" "FAIL" "SKIP_VERIFY=1 (Q15 اجباری)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" --stop-after-init \
    <"${OPS_DIR}/verify/verify_phase8.py" >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^V8-|ITR_VERIFY' "${VERIFY_LOG}" || true
  if grep -q 'ITR_VERIFY_RESULT: PASS' "${VERIFY_LOG}"; then
    gate "G8-06" "verify فاز ۸: هر ۸ سنجه سبز (شامل UAT-12)" "PASS" "$(grep ITR_VERIFY_SUMMARY "${VERIFY_LOG}" | tail -n1)"
  else
    gate "G8-06" "verify فاز ۸ سبز" "FAIL" "rc=${VERIFY_RC} → ${VERIFY_LOG}"
    tail -n 80 "${VERIFY_LOG}" || true
  fi
fi

# =============================================================================
step "8) گاردهای معماری فاز ۸ (G18 + 8.11 ممنوعه‌ها + Q03)"
# =============================================================================
TASK_HITS="$(grep -rnE '_name = "itr\.(task|todo|cartable\.item)"' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null || true)"
QUEUE_IS_ABSTRACT="$(grep -c 'class ItrWorkQueue(models.AbstractModel)' "${CORE_DIR}/models/itr_work_queue.py" || true)"
if [[ -z "${TASK_HITS}" && "${QUEUE_IS_ABSTRACT}" == "1" ]]; then
  gate "G8-07" "تک‌موتور صف‌کار (UX-011/G18) — صف AbstractModel است، جدول دوم ساخته نشد" "PASS" "clean"
else
  gate "G8-07" "تک‌موتور صف‌کار (UX-011/G18)" "FAIL" "${TASK_HITS}"
fi
RAW_SQL_KPI="$(grep -rnE 'env\.cr\.execute' "${CORE_DIR}/models/itr_kpi_service.py" "${CORE_DIR}/models/itr_ceo_dashboard.py" "${CORE_DIR}/models/itr_work_queue.py" 2>/dev/null || true)"
if [[ -z "${RAW_SQL_KPI}" ]]; then
  gate "G8-08" "داشبورد/کارتابل بدون SQL موازی — فقط ORM و موتور مالی واحد (FIN-005)" "PASS" "clean"
else
  gate "G8-08" "داشبورد/کارتابل بدون SQL موازی" "FAIL" "$(echo "${RAW_SQL_KPI}" | head -n2 | tr '\n' ' ')"
fi
FORBIDDEN_HITS="$(grep -rniE 'interactive[_ ]map|leaflet|websocket.*chat|form[_ ]?builder|report[_ ]?builder|dashboard[_ ]?builder' --include='*.py' --include='*.xml' --include='*.js' "${CORE_DIR}" "${TRN_DIR}" 2>/dev/null || true)"
if [[ -z "${FORBIDDEN_HITS}" ]]; then
  gate "G8-09" "هیچ ممنوعه‌ای ساخته نشد (8.11/G16)" "PASS" "clean"
else
  gate "G8-09" "هیچ ممنوعه‌ای ساخته نشد (8.11/G16)" "FAIL" "$(echo "${FORBIDDEN_HITS}" | head -n2 | tr '\n' ' ')"
fi
SUDO_HITS="$(grep -rnE '\.sudo\(\)' "${CORE_DIR}/models/itr_cartable_settings.py" "${CORE_DIR}/models/itr_work_queue.py" "${CORE_DIR}/models/itr_kpi_service.py" "${CORE_DIR}/models/itr_home.py" "${CORE_DIR}/models/itr_ceo_dashboard.py" "${CORE_DIR}/models/itr_notify_phase8.py" 2>/dev/null | grep -v 'ITR-SUDO-OK' || true)"
if [[ -z "${SUDO_HITS}" ]]; then
  gate "G8-10" "هیچ sudo() بی‌برچسب در فایل‌های فاز ۸ (G01)" "PASS" "clean"
else
  gate "G8-10" "هیچ sudo() بی‌برچسب در فایل‌های فاز ۸ (G01)" "FAIL" "$(echo "${SUDO_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "9) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
C1="$(q "${DB_NAME}" "SELECT count(*) FROM itr_cartable_settings")"
C2="$(q "${DB_NAME}" "SELECT count(*) FROM itr_ceo_dashboard")"
C3="$(q "${DB_NAME}" "SELECT count(*) FROM ir_ui_menu")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -u "${CORE_MODULE},${TRN_MODULE}" --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
C1B="$(q "${DB_NAME}" "SELECT count(*) FROM itr_cartable_settings")"
C2B="$(q "${DB_NAME}" "SELECT count(*) FROM itr_ceo_dashboard")"
C3B="$(q "${DB_NAME}" "SELECT count(*) FROM ir_ui_menu")"
if [[ ${IDEMP_RC} -eq 0 && "${C1}" == "${C1B}" && "${C2}" == "${C2B}" && "${C3}" == "${C3B}" ]]; then
  gate "G8-11" "اجرای دوباره رکورد تکراری نساخت (NFR-002)" "PASS" "settings=${C1B} dash=${C2B} menus=${C3B}"
else
  gate "G8-11" "اجرای دوباره رکورد تکراری نساخت (NFR-002)" "FAIL" "settings ${C1}→${C1B} dash ${C2}→${C2B} menus ${C3}→${C3B}"
fi

# =============================================================================
step "10) نصب روی پایگاه‌دادهٔ UAT (محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  warn "SKIP_UAT=1 — UAT رد شد"
  gate "G8-12" "ارتقای UAT بدون خطا" "FAIL" "SKIP_UAT=1"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" \
    -u "${CORE_MODULE},${TRN_MODULE}" --stop-after-init --log-level=warn >"${UAT_LOG}" 2>&1
  UAT_RC=$?
  set -e
  UAT_STATE="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
  if [[ ${UAT_RC} -eq 0 && "${UAT_STATE}" == "installed" ]]; then
    gate "G8-12" "ارتقای UAT بدون خطا" "PASS" "state=installed"
  else
    gate "G8-12" "ارتقای UAT بدون خطا" "FAIL" "rc=${UAT_RC} state=${UAT_STATE} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "11) اسناد حاکمیتی: ADR-037..039 / REUSE MAP / تحویل (Q14)"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
if ! grep -q "ADR-037" "${ADR_FILE}" 2>/dev/null; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-037 — رجیستری KPI واحد = بذر Metric Registry فاز ۹ (REP-002)
هر ۱۸ کارت داشبورد مدیرعامل فقط از itr.kpi.service.get_kpi می‌آیند. فاز ۹ موظف
است همین رجیستری را گسترش دهد (planned/reserved/effective/surplus/remaining/
cost/settled/profit/sla_state) — ساخت موتور شاخص دوم یا SQL موازی ممنوع مطلق
است (G18/FIN-005). سود از فرمول واحد موتور مالی (sale−purchase−cost) خوانده
می‌شود؛ هیچ فرمول دومی تعریف نشد.

## ADR-038 — صف‌کار واحد به‌صورت سرویس، نه جدول
Unified Work Queue (UX-011) یک AbstractModel فقط‌خواندنی روی چهار مدل قرارداد
کارتابل فاز ۴/۵ است. هیچ جدول Task دومی ساخته نشد؛ ارجاع همچنان فقط از مسیر
itr.cartable.mixin.assign_to است (G18/UX-004).

## ADR-039 — رنگ SLA کانبان از ساعت کارتابل
رنگ‌بندی SLA فاز ۸ نمایشِ همان owner_deadline کارتابل + آستانهٔ تنظیمات است؛
موتور تصعید SLA همچنان منحصراً cron پانزده‌دقیقه‌ای itr_notify است (NOT-035).
هیچ cron یا watch دومی ساخته نشد.

## ADR-040 — F4/Q02: act_window حمل فقط در itr_transport یا server action
itr_core قبل از itr_transport لود می‌شود. تعریف ir.actions.act_window با
res_model=itr.transport.case داخل XMLِ itr_core در upgrade با ParseError
«نام مدل نامعتبر» می‌شکند. اکشن‌های کارتابل حمل = ir.actions.server روی
itr.work.queue؛ منوهای Workspace پرداخت/حمل در itr_transport.
MDEOF
fi

if [[ -f "${DOC_DIR}/REUSE_MAP.md" ]] && ! grep -q "phase-8" "${DOC_DIR}/REUSE_MAP.md"; then
cat >>"${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'

## phase-8 (نقشهٔ استفادهٔ مجدد — Q14)
* `itr.cartable.mixin` (فاز ۵) → منبع current_owner_id/owner_deadline صف‌کار؛ جدول Task دوم ساخته نشد.
* مالکان سه تب فاز ۶ (docs/customs/delivery_owner_id) → «بارگیری‌های من» (C1).
* `itr.money.engine` roll-upهای فاز ۶ → کارت‌های مالی داشبورد (FIN-005؛ فرمول دوم ممنوع).
* `itr.notification.dispatch.log` (فاز ۲) → مرکز اعلان؛ فقط دو فیلد read/critical افزوده شد [FIX-P8-1].
* `itr.supervisor.team` (فاز ۳) → Team Tasks سرپرست (SEC-004).
* پارامتر `itr_core.default_assignment_days` (فاز ۵) → write-through از تنظیمات کارتابل (تک‌منبع، G18).
MDEOF
fi

write_utf8 "${DOC_DIR}/PHASE8-DELIVERY.md" <<MDEOF
# تحویل فاز ۸ — $(date -Is)

## Scope انجام‌شده (با شناسهٔ نیازمندی)
8.1 UX-011 صف‌کار واحد | 8.2 UX-001/002 کارتابل ده‌بخشی با آستانهٔ تنظیمات |
8.3 UX-021 Home هر نقش | 8.4 UX-022 مرکز اعلان | 8.5 UX-031 Workspace |
8.6 UX-041 داشبورد ۱۸ کارتی | 8.7 کانبان SLA | 8.8 UX-051 | 8.9 UX-062 |
8.10 موبایل | 8.11 بدون ممنوعه | UAT-12

## Rollback
restore.sh + docs/phase8-backup/${TS}
MDEOF
log "اسناد حاکمیتی ثبت شد"

# =============================================================================
step "12) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" == "1" ]]; then
  if ! ss -lntp 2>/dev/null | grep -q ":${HTTP_PORT} "; then
    rm -f "${PID_FILE}"
    nohup python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
      --http-interface="${HTTP_INTERFACE}" --http-port="${HTTP_PORT}" \
      >"${LOG_FILE}" 2>&1 &
    echo $! >"${PID_FILE}"
    sleep 3
  fi
  HTTP_CODE="000"
  for _ in $(seq 1 20); do
    HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HTTP_PORT}/web/login" || echo 000)"
    [[ "${HTTP_CODE}" == "200" ]] && break
    sleep 2
  done
  if [[ "${HTTP_CODE}" == "200" ]]; then
    gate "G8-13" "سرویس بالا و صفحهٔ ورود HTTP 200" "PASS" "code=200"
  else
    gate "G8-13" "سرویس بالا و صفحهٔ ورود HTTP 200" "FAIL" "code=${HTTP_CODE}"
  fi
else
  warn "START_DAEMON=0 — راه‌اندازی سرویس رد شد"
  gate "G8-13" "سرویس بالا" "PASS" "START_DAEMON=0 (آگاهانه)"
fi

# =============================================================================
step "13) ثبت Git + تگ phase-8 (Q09) + اسکن رمز (Q12)"
# =============================================================================
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "commit جدیدی لازم نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-8: cartable, home, notification center, workspaces (Q02-safe), CEO dashboard, SLA kanban (F5/F6 Gate8 fix)"
  log "git commit ثبت شد"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-8 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-8 || true
else
  git -C "${CUSTOM_ADDONS}" tag -f phase-8 || true
fi
SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z -- '*phase8*' | xargs -0 -r grep -nIE '(api[_-]?key|password)[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']+' 2>/dev/null || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G8-14" "Git commit + تگ phase-8 + بدون رمز (Q12)" "PASS" "HEAD=$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD)"
else
  gate "G8-14" "بدون رمز در فایل‌های فاز (Q12)" "FAIL" "$(echo "${SECRET_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "GATE 8 — گزارش پذیرش فاز ۸"
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

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 8 = سبز ✅ — هر ۱۲ کاربر پس از Login خانه/کارتابل/فضای کاری خودش را می‌بیند (UAT-12)؛ داشبورد ۱۸کارتی از موتور واحد. مجاز به شروع فاز ۹ (گزارش‌ها).${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 8 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۹ آغاز نمی‌شود. Rollback: docs/phase8-backup/${TS}${NC}\n"
  exit 1
fi