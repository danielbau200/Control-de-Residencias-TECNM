"""
Servidor Backend Seguro (Flask + PostgreSQL 16 vía Procedimientos Almacenados)
Puerto por defecto: 8000 (sirve tanto los archivos estáticos del frontend como /api/*).
"""
import json
import os
import smtplib
from email.message import EmailMessage
from pathlib import Path
from urllib.parse import urlencode
from flask import Flask, jsonify, redirect, request, send_from_directory

from pg_client import PGError, call_proc, execute_query, fetch_one

BASE_DIR = Path(__file__).resolve().parent.parent
ALLOWED_ROLES = {"GESTION_1", "ACADEMIA"}

app = Flask(__name__, static_folder=None)


def _get_role() -> str:
    role = (request.headers.get("X-System-Role") or "").strip().upper()
    if role not in ALLOWED_ROLES:
        raise PGError(f'Rol de operación inválido o ausente: "{role}".', "42501")
    return role


def _clean_opt(val):
    if val is None:
        return None
    s = str(val).strip()
    return s if s != "" else None


def _handle_pg_error(err: PGError):
    code = err.sqlstate or ""
    if code == "42501":
        status = 403
    elif code in ("P0001", "22P02", "23505", "23503", "23502", "22007"):
        status = 400
    elif code.startswith("08"):
        status = 503
    else:
        status = 500
    return jsonify({"ok": False, "error": err.message, "sqlstate": code}), status


@app.after_request
def add_security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    response.headers["Referrer-Policy"] = "no-referrer"
    if request.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store"
    return response


# =============================================================================
# API REST CONECTADA EXCLUSIVAMENTE A PROCEDIMIENTOS ALMACENADOS Y FUNCIONES
# =============================================================================

@app.get("/api/health")
def api_health():
    try:
        row = fetch_one("SELECT current_user AS db_user, current_database() AS db_name")
        return jsonify({
            "ok": True,
            "dbUser": row["db_user"],
            "dbName": row["db_name"],
            "mode": "PostgreSQL 16 · Stored Procedures (Zero-Direct-Table-Access)"
        })
    except PGError as err:
        return _handle_pg_error(err)


@app.get("/api/bootstrap")
def api_bootstrap():
    try:
        row = fetch_one("SELECT fn_api_obtener_estado_inicial()::TEXT AS payload")
        payload = json.loads(row["payload"])
        return jsonify({"ok": True, "data": payload})
    except PGError as err:
        return _handle_pg_error(err)


@app.get("/api/oficios/siguiente/<tipo>")
def api_siguiente_folio(tipo):
    try:
        anio = request.args.get("anio", 2026, type=int)
        row = fetch_one("SELECT fn_siguiente_folio_oficio($1, $2) AS folio", [tipo.upper(), anio])
        return jsonify({"ok": True, "folio": row["folio"]})
    except PGError as err:
        return _handle_pg_error(err)


@app.get("/api/bitacora")
def api_bitacora():
    try:
        usuario = request.args.get("usuario", "ALL")
        limite = request.args.get("limite", 200, type=int)
        row = fetch_one("SELECT fn_api_obtener_bitacora($1, $2)::TEXT AS payload", [usuario, limite])
        return jsonify({"ok": True, "bitacora": json.loads(row["payload"])})
    except PGError as err:
        return _handle_pg_error(err)


@app.post("/api/expedientes")
def api_save_expediente():
    try:
        role = _get_role()
        body = request.get_json(silent=True) or {}
        exp_id = body.get("id")

        if exp_id:
            call_proc(
                """
                CALL sp_actualizar_expediente_completo(
                    $1::INT, $2::VARCHAR, $3::VARCHAR, $4::VARCHAR, $5::VARCHAR, $6::VARCHAR,
                    $7::estado_servicio_social_enum, $8::estado_expediente_enum,
                    $9::TEXT, $10::VARCHAR, $11::VARCHAR, $12::VARCHAR, $13::VARCHAR,
                    $14::DATE, $15::DATE, $16::VARCHAR, $17::DATE, $18::DATE, $19::DATE,
                    $20::TEXT, $21::BOOLEAN, $22::dictamen_academia_enum, $23::VARCHAR,
                    $24::VARCHAR, $25::VARCHAR, $26::DATE, $27::VARCHAR
                )
                """,
                [
                    int(exp_id),
                    body.get("control"),
                    body.get("nombre"),
                    _clean_opt(body.get("correoInstitucional")),
                    body.get("semestre") or "Ago-Dic 2026",
                    body.get("especialidad") or "INDUSTRIAL GENERAL",
                    body.get("servicioSocial") or "Por verificar",
                    body.get("estado") or "En Revisión por Academia",
                    body.get("proyecto") or "",
                    body.get("empresa") or "",
                    _clean_opt(body.get("asesorExterno")),
                    _clean_opt(body.get("horario")),
                    _clean_opt(body.get("periodo")),
                    _clean_opt(body.get("fechaEntregaFisica")),
                    _clean_opt(body.get("fechaEntregaAcademia")),
                    _clean_opt(body.get("oficioAutorizacion")),
                    _clean_opt(body.get("fechaImpresion")),
                    _clean_opt(body.get("notificadoAlumno")),
                    _clean_opt(body.get("fechaEnvioAutCorreo")),
                    _clean_opt(body.get("observaciones")),
                    bool(body.get("actualizarAcademia", False)),
                    _clean_opt(body.get("revisadoAcademia")),
                    _clean_opt(body.get("asesorInterno")),
                    _clean_opt(body.get("folioAcademia")),
                    _clean_opt(body.get("oficioAsesorInterno")),
                    _clean_opt(body.get("fechaEnvioAsesorCorreo")),
                    role,
                ],
            )
            saved_id = int(exp_id)
        else:
            out = call_proc(
                """
                CALL sp_registrar_solicitud_anteproyecto(
                    $1::VARCHAR, $2::VARCHAR, $3::VARCHAR, $4::VARCHAR, $5::VARCHAR,
                    $6::TEXT, $7::VARCHAR, $8::VARCHAR, $9::VARCHAR, $10::VARCHAR,
                    $11::estado_servicio_social_enum, $12::DATE, $13::TEXT, $14::VARCHAR, NULL
                )
                """,
                [
                    body.get("control"),
                    body.get("nombre"),
                    _clean_opt(body.get("correoInstitucional")),
                    body.get("semestre") or "Ago-Dic 2026",
                    body.get("especialidad") or "INDUSTRIAL GENERAL",
                    body.get("proyecto") or "",
                    body.get("empresa") or "",
                    _clean_opt(body.get("asesorExterno")),
                    _clean_opt(body.get("horario")),
                    _clean_opt(body.get("periodo")),
                    body.get("servicioSocial") or "Por verificar",
                    _clean_opt(body.get("fechaEntregaFisica")),
                    _clean_opt(body.get("observaciones")),
                    role,
                ],
            )
            saved_id = int(out["p_id_expediente_out"])

        boot = fetch_one("SELECT fn_api_obtener_estado_inicial()::TEXT AS payload")
        return jsonify({"ok": True, "id": saved_id, "data": json.loads(boot["payload"])})
    except PGError as err:
        return _handle_pg_error(err)


@app.post("/api/expedientes/<int:exp_id>/aceptar-pa")
def api_aceptar_pa(exp_id):
    try:
        role = _get_role()
        body = request.get_json(silent=True) or {}
        out = call_proc(
            "CALL sp_gestion_aceptar_proyecto($1::INT, $2::VARCHAR, $3::DATE, $4::DATE, $5::VARCHAR, NULL)",
            [
                exp_id,
                _clean_opt(body.get("oficioAutorizacion")),
                _clean_opt(body.get("fechaEntregaAcademia")),
                _clean_opt(body.get("fechaImpresion")),
                role,
            ],
        )
        boot = fetch_one("SELECT fn_api_obtener_estado_inicial()::TEXT AS payload")
        return jsonify({"ok": True, "oficio": out.get("p_oficio_generado"), "data": json.loads(boot["payload"])})
    except PGError as err:
        return _handle_pg_error(err)


@app.post("/api/expedientes/<int:exp_id>/emitir-pb")
def api_emitir_pb(exp_id):
    try:
        role = _get_role()
        body = request.get_json(silent=True) or {}
        out = call_proc(
            "CALL sp_gestion_emitir_oficio_pb($1::INT, $2::VARCHAR, $3::DATE, $4::VARCHAR, NULL)",
            [
                exp_id,
                _clean_opt(body.get("oficioAsesorInterno")),
                _clean_opt(body.get("fechaEnvioAsesorCorreo")),
                role,
            ],
        )
        boot = fetch_one("SELECT fn_api_obtener_estado_inicial()::TEXT AS payload")
        return jsonify({"ok": True, "oficio": out.get("p_oficio_generado"), "data": json.loads(boot["payload"])})
    except PGError as err:
        return _handle_pg_error(err)


def _outlook_config():
    email_addr = (os.environ.get("OUTLOOK_EMAIL") or "").strip()
    password = os.environ.get("OUTLOOK_PASSWORD") or ""
    host = (os.environ.get("OUTLOOK_SMTP_HOST") or "smtp.office365.com").strip()
    port = int(os.environ.get("OUTLOOK_SMTP_PORT") or "587")
    return {
        "configured": bool(email_addr and password),
        "email": email_addr,
        "password": password,
        "host": host,
        "port": port,
    }


@app.get("/api/outlook/status")
def api_outlook_status():
    cfg = _outlook_config()
    return jsonify({
        "ok": True,
        "smtpConfigured": cfg["configured"],
        "senderEmail": cfg["email"],
        "smtpHost": cfg["host"],
    })


@app.post("/api/expedientes/<int:exp_id>/notificar")
def api_notificar(exp_id):
    try:
        role = _get_role()
        body = request.get_json(silent=True) or {}
        call_proc(
            "CALL sp_gestion_notificar_alumno($1::INT, $2::VARCHAR, $3::VARCHAR, $4::VARCHAR, $5::DATE, $6::VARCHAR)",
            [
                exp_id,
                _clean_opt(body.get("correoDestino")),
                _clean_opt(body.get("asunto")),
                _clean_opt(body.get("medioEnvio")) or "Outlook Web",
                _clean_opt(body.get("fechaNotificacion")),
                role,
            ],
        )
        boot = fetch_one("SELECT fn_api_obtener_estado_inicial()::TEXT AS payload")
        return jsonify({"ok": True, "data": json.loads(boot["payload"])})
    except PGError as err:
        return _handle_pg_error(err)


@app.post("/api/expedientes/<int:exp_id>/notificar-outlook")
def api_notificar_outlook(exp_id):
    try:
        role = _get_role()
        if role != "GESTION_1":
            raise PGError(f'Acceso denegado: el rol "{role}" no tiene autorización para enviar avisos Outlook (requiere: GESTION_1).', "42501")

        body = request.get_json(silent=True) or {}
        correo = (_clean_opt(body.get("correoDestino")) or "").lower()
        asunto = _clean_opt(body.get("asunto")) or "Aviso de Residencias Profesionales — Oficios listos"
        mensaje = (_clean_opt(body.get("mensaje")) or "").strip()
        modo = (_clean_opt(body.get("modo")) or "outlook_web").lower()

        if modo != "manual" and ("@" not in correo or "." not in correo.split("@")[-1]):
            return jsonify({"ok": False, "error": "Ingresa un correo institucional válido (ejemplo@cdmadero.tecnm.mx)."}), 400

        outlook_web_url = "https://outlook.office.com/mail/deeplink/compose?" + urlencode({
            "to": correo,
            "subject": asunto,
            "body": mensaje,
        })
        mailto_url = f"mailto:{correo}?" + urlencode({
            "subject": asunto,
            "body": mensaje,
        })

        if modo == "smtp":
            cfg = _outlook_config()
            if not cfg["configured"]:
                return jsonify({
                    "ok": True,
                    "sentViaSmtp": False,
                    "needsConfig": True,
                    "outlookWebUrl": outlook_web_url,
                    "mailtoUrl": mailto_url,
                    "message": "No hay credenciales SMTP de Outlook configuradas en el servidor. Puedes enviarlo en 1 clic abriendo Outlook Web.",
                })

            msg = EmailMessage()
            msg["Subject"] = asunto
            msg["From"] = cfg["email"]
            msg["To"] = correo
            msg.set_content(mensaje)
            try:
                with smtplib.SMTP(cfg["host"], cfg["port"], timeout=15) as smtp:
                    smtp.ehlo()
                    smtp.starttls()
                    smtp.ehlo()
                    smtp.login(cfg["email"], cfg["password"])
                    smtp.send_message(msg)
            except Exception as exc:
                return jsonify({
                    "ok": False,
                    "error": f"No se pudo enviar vía Outlook SMTP ({exc}). Puedes usar 'Abrir en Outlook Web'.",
                    "outlookWebUrl": outlook_web_url,
                }), 502

            medio_label = "Outlook SMTP"
        elif modo == "manual":
            medio_label = "Aviso Manual"
        else:
            medio_label = "Outlook Web"

        call_proc(
            "CALL sp_gestion_notificar_alumno($1::INT, $2::VARCHAR, $3::VARCHAR, $4::VARCHAR, $5::DATE, $6::VARCHAR)",
            [exp_id, correo or None, asunto, medio_label, None, role],
        )
        boot = fetch_one("SELECT fn_api_obtener_estado_inicial()::TEXT AS payload")
        return jsonify({
            "ok": True,
            "sentViaSmtp": modo == "smtp",
            "registered": True,
            "outlookWebUrl": outlook_web_url,
            "mailtoUrl": mailto_url,
            "data": json.loads(boot["payload"]),
        })
    except PGError as err:
        return _handle_pg_error(err)


@app.post("/api/expedientes/<int:exp_id>/asignar-asesor")
def api_asignar_asesor(exp_id):
    try:
        role = _get_role()
        body = request.get_json(silent=True) or {}
        id_doc = body.get("idDocente")
        call_proc(
            """
            CALL sp_academia_asignar_asesor(
                $1::INT, $2::INT, $3::VARCHAR, $4::VARCHAR,
                $5::dictamen_academia_enum, $6::BOOLEAN, $7::VARCHAR, $8::BOOLEAN
            )
            """,
            [
                exp_id,
                int(id_doc) if id_doc else None,
                _clean_opt(body.get("asesorInterno")),
                _clean_opt(body.get("folioAcademia")),
                _clean_opt(body.get("dictamen")) or "ASIGNADO",
                bool(body.get("autoOficioPB", False)),
                role,
                bool(body.get("correccionAdmin", False)),
            ],
        )
        boot = fetch_one("SELECT fn_api_obtener_estado_inicial()::TEXT AS payload")
        return jsonify({"ok": True, "data": json.loads(boot["payload"])})
    except PGError as err:
        return _handle_pg_error(err)


@app.post("/api/expedientes/<int:exp_id>/excepcion")
def api_cambiar_excepcion(exp_id):
    try:
        role = _get_role()
        body = request.get_json(silent=True) or {}
        call_proc(
            """
            CALL sp_cambiar_estado_excepcion(
                $1::INT, $2::estado_expediente_enum, $3::estado_servicio_social_enum,
                $4::TEXT, $5::VARCHAR
            )
            """,
            [
                exp_id,
                _clean_opt(body.get("estado")),
                _clean_opt(body.get("servicioSocial")),
                _clean_opt(body.get("observaciones")),
                role,
            ],
        )
        boot = fetch_one("SELECT fn_api_obtener_estado_inicial()::TEXT AS payload")
        return jsonify({"ok": True, "data": json.loads(boot["payload"])})
    except PGError as err:
        return _handle_pg_error(err)


# =============================================================================
# SERVIDO SEGURO DE ARCHIVOS ESTÁTICOS DEL FRONTEND
# =============================================================================

@app.get("/")
def serve_root():
    return redirect("/fronted/pages/gestion-vinculacion.html", code=302)


@app.get("/fronted/<path:filename>")
def serve_fronted(filename):
    return send_from_directory(BASE_DIR / "fronted", filename)


if __name__ == "__main__":
    host = os.environ.get("FLASK_HOST", "::")
    port = int(os.environ.get("FLASK_PORT", "8000"))
    app.run(host=host, port=port, debug=False)
