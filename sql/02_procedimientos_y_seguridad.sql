-- ============================================================================
-- CAPA DE SEGURIDAD, RBAC Y PROCEDIMIENTOS ALMACENADOS (ZERO-DIRECT-TABLE-ACCESS)
-- Base de Datos: residencias_industrial_db (PostgreSQL 16)
-- Arquitectura: El usuario de aplicación (app_residencias_user) NO tiene permisos
--               sobre las tablas; únicamente ejecuta SPs y Funciones SECURITY DEFINER.
-- ============================================================================

SET client_encoding = 'UTF8';

-- ============================================================================
-- 1. ROL DE APLICACIÓN CON MÍNIMOS PRIVILEGIOS (MÍNIMO ACCESO)
-- IMPORTANTE: Antes de ejecutar en un servidor nuevo, cambia
-- 'CAMBIAR_CONTRASENA_SEGURA' por una contraseña fuerte que coincida con
-- la variable PGPASSWORD de tu archivo .env.
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_residencias_user') THEN
        CREATE ROLE app_residencias_user
            LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT
            PASSWORD 'CAMBIAR_CONTRASENA_SEGURA';
    ELSE
        ALTER ROLE app_residencias_user
            WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT
            PASSWORD 'CAMBIAR_CONTRASENA_SEGURA';
    END IF;
END $$;

-- Revocar acceso directo a tablas, vistas y secuencias
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, app_residencias_user;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, app_residencias_user;
REVOKE CREATE ON SCHEMA public FROM PUBLIC, app_residencias_user;

GRANT CONNECT ON DATABASE residencias_industrial_db TO app_residencias_user;
GRANT USAGE ON SCHEMA public TO app_residencias_user;

-- ============================================================================
-- 2. LIMPIEZA DE SOBRECARGAS PREVIAS DE PROCEDIMIENTOS / FUNCIONES
-- ============================================================================
DROP PROCEDURE IF EXISTS sp_registrar_solicitud_anteproyecto(VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, DATE, TEXT, VARCHAR);
DROP PROCEDURE IF EXISTS sp_registrar_solicitud_anteproyecto(VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, DATE, TEXT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS sp_registrar_solicitud_anteproyecto(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, DATE, TEXT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS sp_actualizar_expediente_completo(INT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, estado_expediente_enum, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, DATE, VARCHAR, DATE, DATE, DATE, TEXT, BOOLEAN, dictamen_academia_enum, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR);
DROP PROCEDURE IF EXISTS sp_actualizar_expediente_completo(INT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, estado_expediente_enum, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, DATE, VARCHAR, DATE, DATE, DATE, TEXT, BOOLEAN, dictamen_academia_enum, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR);
DROP PROCEDURE IF EXISTS sp_gestion_aceptar_proyecto(INT, VARCHAR, DATE, DATE, VARCHAR);
DROP PROCEDURE IF EXISTS sp_gestion_aceptar_proyecto(INT, VARCHAR, DATE, DATE, VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS sp_gestion_emitir_oficio_pb(INT, VARCHAR, DATE, VARCHAR);
DROP PROCEDURE IF EXISTS sp_gestion_emitir_oficio_pb(INT, VARCHAR, DATE, VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS sp_gestion_notificar_alumno(INT, DATE, VARCHAR);
DROP PROCEDURE IF EXISTS sp_gestion_notificar_alumno(INT, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR);
DROP PROCEDURE IF EXISTS sp_academia_asignar_asesor(INT, INT, VARCHAR, BOOLEAN, VARCHAR);
DROP PROCEDURE IF EXISTS sp_academia_asignar_asesor(INT, INT, VARCHAR, VARCHAR, dictamen_academia_enum, BOOLEAN, VARCHAR, BOOLEAN);
DROP PROCEDURE IF EXISTS sp_cambiar_estado_excepcion(INT, estado_expediente_enum, estado_servicio_social_enum, TEXT, VARCHAR);

-- ============================================================================
-- 3. HELPER RBAC INTERNO (VALIDACIÓN DE ROL ACTIVO EN BASE DE DATOS)
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_validar_rol_activo(
    p_usuario VARCHAR,
    p_roles_permitidos TEXT[]
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol rol_sistema_enum;
    v_activo BOOLEAN;
    v_norm VARCHAR;
BEGIN
    v_norm := UPPER(TRIM(COALESCE(p_usuario, '')));
    IF v_norm = '' THEN
        RAISE EXCEPTION 'Acceso denegado: no se especificó un rol de usuario válido.'
            USING ERRCODE = '42501';
    END IF;

    SELECT rol, activo
    INTO v_rol, v_activo
    FROM usuarios_sistema
    WHERE rol::TEXT = v_norm
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Acceso denegado: el rol "%" no existe en usuarios_sistema.', v_norm
            USING ERRCODE = '42501';
    END IF;

    IF NOT v_activo THEN
        RAISE EXCEPTION 'Acceso denegado: el usuario con rol "%" está desactivado.', v_norm
            USING ERRCODE = '42501';
    END IF;

    IF NOT (v_rol::TEXT = ANY(p_roles_permitidos)) THEN
        RAISE EXCEPTION 'Acceso denegado: el rol "%" no tiene autorización para esta operación (requiere: %).',
            v_rol::TEXT, array_to_string(p_roles_permitidos, ', ')
            USING ERRCODE = '42501';
    END IF;

    RETURN v_rol::TEXT;
END;
$$;

-- ============================================================================
-- 4. FUNCIONES SEGURAS DE LECTURA Y GENERACIÓN DE FOLIOS (SECURITY DEFINER)
-- ============================================================================

-- 4.1 Generador de siguiente folio consecutivo P.A / P.B
CREATE OR REPLACE FUNCTION fn_siguiente_folio_oficio(
    p_tipo_oficio VARCHAR,
    p_anio INT DEFAULT 2026
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_prefijo VARCHAR;
    v_max_num INT := 0;
BEGIN
    v_prefijo := CASE WHEN UPPER(TRIM(p_tipo_oficio)) = 'PA' THEN 'P.A' ELSE 'P.B' END;

    IF UPPER(TRIM(p_tipo_oficio)) = 'PA' THEN
        SELECT COALESCE(MAX((regexp_match(oficio_autorizacion, 'P\.A(\d+)/' || p_anio::TEXT))[1]::INT), 0)
        INTO v_max_num
        FROM expedientes_residencias
        WHERE oficio_autorizacion ~ ('^P\.A\d+/' || p_anio::TEXT);
    ELSE
        SELECT COALESCE(MAX((regexp_match(oficio_asignacion_asesor, 'P\.B(\d+)/' || p_anio::TEXT))[1]::INT), 0)
        INTO v_max_num
        FROM expedientes_residencias
        WHERE oficio_asignacion_asesor ~ ('^P\.B\d+/' || p_anio::TEXT);
    END IF;

    RETURN v_prefijo || LPAD((v_max_num + 1)::TEXT, 3, '0') || '/' || p_anio::TEXT;
END;
$$;

-- 4.2 Bootstrap JSONB completo para el Frontend (sin acceso directo a tablas)
CREATE OR REPLACE FUNCTION fn_api_obtener_estado_inicial()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_residencias JSONB;
    v_maestros JSONB;
    v_bitacora JSONB;
    v_kpis JSONB;
    v_usuarios JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    INTO v_residencias
    FROM (
        SELECT
            e.id_expediente AS "id",
            e.numero_control AS "control",
            a.nombre_completo AS "nombre",
            COALESCE(a.correo_institucional, '') AS "correoInstitucional",
            e.semestre AS "semestre",
            a.especialidad AS "especialidad",
            COALESCE(e.titulo_anteproyecto, '') AS "proyecto",
            COALESCE(emp.nombre_empresa, e.nombre_empresa_texto, '') AS "empresa",
            COALESCE(e.horario_asistencia, '') AS "horario",
            COALESCE(e.periodo_realizacion, '') AS "periodo",
            COALESCE(e.asesor_externo, '') AS "asesorExterno",
            COALESCE(e.nombre_asesor_interno_texto, d.nombre_docente, '') AS "asesorInterno",
            COALESCE(e.folio_control_academia, '') AS "folioAcademia",
            COALESCE(TO_CHAR(e.fecha_entrega_fisica, 'YYYY-MM-DD'), e.nota_entrega_fisica, '') AS "fechaEntregaFisica",
            COALESCE(TO_CHAR(e.fecha_entrega_academia, 'YYYY-MM-DD'), '') AS "fechaEntregaAcademia",
            e.revisado_academia::TEXT AS "revisadoAcademia",
            COALESCE(e.oficio_autorizacion, '') AS "oficioAutorizacion",
            COALESCE(TO_CHAR(e.fecha_impresion_oficio_aut, 'YYYY-MM-DD'), '') AS "fechaImpresion",
            COALESCE(TO_CHAR(e.fecha_notificado_alumno, 'YYYY-MM-DD'), '') AS "notificadoAlumno",
            COALESCE(e.correo_aviso_enviado, '') AS "correoAvisoEnviado",
            COALESCE(e.medio_notificacion, '') AS "medioNotificacion",
            COALESCE(TO_CHAR(e.fecha_envio_aut_correo, 'YYYY-MM-DD'), '') AS "fechaEnvioAutCorreo",
            COALESCE(e.oficio_asignacion_asesor, '') AS "oficioAsesorInterno",
            COALESCE(TO_CHAR(e.fecha_envio_asesor_correo, 'YYYY-MM-DD'), '') AS "fechaEnvioAsesorCorreo",
            a.estado_servicio_social::TEXT AS "servicioSocial",
            e.estado_expediente::TEXT AS "estado",
            COALESCE(e.observaciones, '') AS "observaciones"
        FROM expedientes_residencias e
        JOIN alumnos a ON e.numero_control = a.numero_control
        LEFT JOIN empresas_receptoras emp ON e.id_empresa = emp.id_empresa
        LEFT JOIN docentes_asesores d ON e.id_docente_asesor = d.id_docente
        ORDER BY e.id_expediente ASC
    ) t;

    SELECT COALESCE(jsonb_agg(row_to_json(m)), '[]'::jsonb)
    INTO v_maestros
    FROM (
        SELECT
            id_docente AS "id",
            nombre_docente AS "nombre",
            jornada::TEXT AS "jornada",
            historico_proy_ene_jun AS "proyectosEneJun",
            historico_interno_ene_jun AS "proyectoInternoEneJun",
            historico_proy_ago_dic AS "proyectosAgoDic",
            historico_interno_ago_dic AS "proyectoInternoAgoDic",
            beca AS "beca"
        FROM docentes_asesores
        WHERE activo = TRUE
        ORDER BY id_docente ASC
    ) m;

    SELECT COALESCE(jsonb_agg(row_to_json(b)), '[]'::jsonb)
    INTO v_bitacora
    FROM (
        SELECT
            bm.id_movimiento AS "id",
            bm.id_expediente AS "idExpediente",
            COALESCE(bm.numero_control, '') AS "control",
            COALESCE(al.nombre_completo, 'Sistema') AS "nombreAlumno",
            bm.usuario_responsable AS "usuario",
            bm.tipo_operacion AS "operacion",
            COALESCE(bm.estado_anterior, '—') AS "estadoAnterior",
            COALESCE(bm.estado_nuevo, '—') AS "estadoNuevo",
            bm.descripcion AS "descripcion",
            TO_CHAR(bm.fecha_movimiento AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "fecha"
        FROM bitacora_movimientos bm
        LEFT JOIN alumnos al ON bm.numero_control = al.numero_control
        ORDER BY bm.id_movimiento DESC
        LIMIT 200
    ) b;

    SELECT jsonb_build_object(
        'total', total_registros,
        'completos', expedientes_completos,
        'pendientesAcademia', pendientes_academia_o_oficio,
        'pausados', tramites_pausados,
        'detenidosSS', detenidos_ss,
        'alertasSS', alertas_servicio_social,
        'pendientesNotificar', pendientes_notificar
    )
    INTO v_kpis
    FROM v_kpis_dashboard;

    SELECT COALESCE(jsonb_agg(row_to_json(u)), '[]'::jsonb)
    INTO v_usuarios
    FROM (
        SELECT id_usuario AS "id", username, nombre_mostrar AS "nombre", rol::TEXT AS "rol", correo, activo
        FROM usuarios_sistema
        WHERE activo = TRUE
        ORDER BY id_usuario ASC
    ) u;

    RETURN jsonb_build_object(
        'residencias', v_residencias,
        'maestros', v_maestros,
        'bitacora', v_bitacora,
        'kpis', v_kpis,
        'usuarios', v_usuarios
    );
END;
$$;

-- 4.3 Obtener detalle de 1 expediente + su bitácora
CREATE OR REPLACE FUNCTION fn_api_obtener_expediente(p_id_expediente INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_exp JSONB;
    v_hist JSONB;
BEGIN
    SELECT row_to_json(t)::jsonb
    INTO v_exp
    FROM (
        SELECT
            e.id_expediente AS "id",
            e.numero_control AS "control",
            a.nombre_completo AS "nombre",
            COALESCE(a.correo_institucional, '') AS "correoInstitucional",
            e.semestre AS "semestre",
            a.especialidad AS "especialidad",
            COALESCE(e.titulo_anteproyecto, '') AS "proyecto",
            COALESCE(emp.nombre_empresa, e.nombre_empresa_texto, '') AS "empresa",
            COALESCE(e.horario_asistencia, '') AS "horario",
            COALESCE(e.periodo_realizacion, '') AS "periodo",
            COALESCE(e.asesor_externo, '') AS "asesorExterno",
            COALESCE(e.nombre_asesor_interno_texto, d.nombre_docente, '') AS "asesorInterno",
            COALESCE(e.folio_control_academia, '') AS "folioAcademia",
            COALESCE(TO_CHAR(e.fecha_entrega_fisica, 'YYYY-MM-DD'), e.nota_entrega_fisica, '') AS "fechaEntregaFisica",
            COALESCE(TO_CHAR(e.fecha_entrega_academia, 'YYYY-MM-DD'), '') AS "fechaEntregaAcademia",
            e.revisado_academia::TEXT AS "revisadoAcademia",
            COALESCE(e.oficio_autorizacion, '') AS "oficioAutorizacion",
            COALESCE(TO_CHAR(e.fecha_impresion_oficio_aut, 'YYYY-MM-DD'), '') AS "fechaImpresion",
            COALESCE(TO_CHAR(e.fecha_notificado_alumno, 'YYYY-MM-DD'), '') AS "notificadoAlumno",
            COALESCE(e.correo_aviso_enviado, '') AS "correoAvisoEnviado",
            COALESCE(e.medio_notificacion, '') AS "medioNotificacion",
            COALESCE(TO_CHAR(e.fecha_envio_aut_correo, 'YYYY-MM-DD'), '') AS "fechaEnvioAutCorreo",
            COALESCE(e.oficio_asignacion_asesor, '') AS "oficioAsesorInterno",
            COALESCE(TO_CHAR(e.fecha_envio_asesor_correo, 'YYYY-MM-DD'), '') AS "fechaEnvioAsesorCorreo",
            a.estado_servicio_social::TEXT AS "servicioSocial",
            e.estado_expediente::TEXT AS "estado",
            COALESCE(e.observaciones, '') AS "observaciones"
        FROM expedientes_residencias e
        JOIN alumnos a ON e.numero_control = a.numero_control
        LEFT JOIN empresas_receptoras emp ON e.id_empresa = emp.id_empresa
        LEFT JOIN docentes_asesores d ON e.id_docente_asesor = d.id_docente
        WHERE e.id_expediente = p_id_expediente
    ) t;

    IF v_exp IS NULL THEN
        RAISE EXCEPTION 'No existe el expediente con ID %', p_id_expediente USING ERRCODE = 'P0001';
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(h)), '[]'::jsonb)
    INTO v_hist
    FROM (
        SELECT
            id_movimiento AS "id",
            usuario_responsable AS "usuario",
            tipo_operacion AS "operacion",
            COALESCE(estado_anterior, '—') AS "estadoAnterior",
            COALESCE(estado_nuevo, '—') AS "estadoNuevo",
            descripcion AS "descripcion",
            TO_CHAR(fecha_movimiento AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "fecha"
        FROM bitacora_movimientos
        WHERE id_expediente = p_id_expediente
        ORDER BY id_movimiento DESC
    ) h;

    RETURN jsonb_build_object('expediente', v_exp, 'historial', v_hist);
END;
$$;

-- 4.4 Obtener carga de docentes
CREATE OR REPLACE FUNCTION fn_api_obtener_carga_docentes()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(jsonb_agg(row_to_json(v)), '[]'::jsonb)
        FROM v_carga_asesores_internos v
    );
END;
$$;

-- 4.5 Obtener bitácora filtrada
CREATE OR REPLACE FUNCTION fn_api_obtener_bitacora(
    p_usuario VARCHAR DEFAULT 'ALL',
    p_limite INT DEFAULT 200
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(jsonb_agg(row_to_json(b)), '[]'::jsonb)
        FROM (
            SELECT
                bm.id_movimiento AS "id",
                bm.id_expediente AS "idExpediente",
                COALESCE(bm.numero_control, '') AS "control",
                COALESCE(al.nombre_completo, 'Sistema') AS "nombreAlumno",
                bm.usuario_responsable AS "usuario",
                bm.tipo_operacion AS "operacion",
                COALESCE(bm.estado_anterior, '—') AS "estadoAnterior",
                COALESCE(bm.estado_nuevo, '—') AS "estadoNuevo",
                bm.descripcion AS "descripcion",
                TO_CHAR(bm.fecha_movimiento AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "fecha"
            FROM bitacora_movimientos bm
            LEFT JOIN alumnos al ON bm.numero_control = al.numero_control
            WHERE (p_usuario IS NULL OR p_usuario = 'ALL' OR bm.usuario_responsable = p_usuario)
            ORDER BY bm.id_movimiento DESC
            LIMIT GREATEST(1, LEAST(COALESCE(p_limite, 200), 500))
        ) b
    );
END;
$$;

-- 4.6 Endurecer fn_buscar_expedientes con SECURITY DEFINER
ALTER FUNCTION fn_buscar_expedientes(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR)
    SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 5. PROCEDIMIENTOS ALMACENADOS DE ESCRITURA (SECURITY DEFINER + RBAC)
-- ============================================================================

-- 5.1 SP 1: Recepción de Solicitud Física en Ventanilla (Hojas Impresas)
CREATE OR REPLACE PROCEDURE sp_registrar_solicitud_anteproyecto(
    p_numero_control VARCHAR,
    p_nombre_alumno VARCHAR,
    p_correo_institucional VARCHAR,
    p_semestre VARCHAR,
    p_especialidad VARCHAR,
    p_titulo_anteproyecto TEXT,
    p_nombre_empresa VARCHAR,
    p_asesor_externo VARCHAR,
    p_horario VARCHAR,
    p_periodo VARCHAR,
    p_estado_servicio_social estado_servicio_social_enum,
    p_fecha_entrega_fisica DATE,
    p_observaciones TEXT,
    p_usuario VARCHAR,
    OUT p_id_expediente_out INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol VARCHAR;
    v_id_empresa INT;
    v_id_expediente INT;
    v_estado_inicial estado_expediente_enum;
    v_ctrl VARCHAR;
    v_nombre VARCHAR;
    v_correo VARCHAR;
BEGIN
    v_rol := fn_validar_rol_activo(p_usuario, ARRAY['GESTION_1']);

    v_ctrl := TRIM(COALESCE(p_numero_control, ''));
    v_nombre := UPPER(TRIM(COALESCE(p_nombre_alumno, '')));
    v_correo := LOWER(NULLIF(TRIM(COALESCE(p_correo_institucional, '')), ''));
    IF v_correo IS NULL AND v_ctrl <> '' THEN
        v_correo := LOWER('l' || v_ctrl || '@cdmadero.tecnm.mx');
    END IF;

    IF LENGTH(v_ctrl) < 6 THEN
        RAISE EXCEPTION 'El número de control "%" debe tener al menos 6 caracteres.', v_ctrl
            USING ERRCODE = 'P0001';
    END IF;
    IF v_nombre = '' THEN
        RAISE EXCEPTION 'El nombre completo del alumno es obligatorio.'
            USING ERRCODE = 'P0001';
    END IF;

    IF p_nombre_empresa IS NOT NULL AND TRIM(p_nombre_empresa) <> '' THEN
        INSERT INTO empresas_receptoras (nombre_empresa)
        VALUES (UPPER(TRIM(p_nombre_empresa)))
        ON CONFLICT (nombre_empresa) DO UPDATE SET activa = TRUE
        RETURNING id_empresa INTO v_id_empresa;
    END IF;

    INSERT INTO alumnos (
        numero_control, nombre_completo, correo_institucional, especialidad, estado_servicio_social, actualizado_en
    ) VALUES (
        v_ctrl, v_nombre, v_correo,
        COALESCE(NULLIF(UPPER(TRIM(p_especialidad)), ''), 'INDUSTRIAL GENERAL'),
        p_estado_servicio_social, NOW()
    )
    ON CONFLICT (numero_control) DO UPDATE
    SET nombre_completo = EXCLUDED.nombre_completo,
        correo_institucional = COALESCE(NULLIF(EXCLUDED.correo_institucional, ''), alumnos.correo_institucional),
        especialidad = EXCLUDED.especialidad,
        estado_servicio_social = EXCLUDED.estado_servicio_social,
        actualizado_en = NOW();

    IF p_estado_servicio_social = 'No Liberado (Irregular)' THEN
        v_estado_inicial := 'Detenido por Servicio Social';
    ELSE
        v_estado_inicial := 'En Revisión por Academia';
    END IF;

    SELECT id_expediente INTO v_id_expediente
    FROM expedientes_residencias
    WHERE numero_control = v_ctrl
    ORDER BY id_expediente DESC
    LIMIT 1;

    IF v_id_expediente IS NOT NULL THEN
        UPDATE expedientes_residencias
        SET semestre = COALESCE(NULLIF(TRIM(p_semestre), ''), semestre),
            titulo_anteproyecto = UPPER(TRIM(p_titulo_anteproyecto)),
            id_empresa = v_id_empresa,
            nombre_empresa_texto = UPPER(TRIM(p_nombre_empresa)),
            asesor_externo = NULLIF(UPPER(TRIM(p_asesor_externo)), ''),
            horario_asistencia = NULLIF(UPPER(TRIM(p_horario)), ''),
            periodo_realizacion = NULLIF(UPPER(TRIM(p_periodo)), ''),
            fecha_entrega_fisica = COALESCE(p_fecha_entrega_fisica, CURRENT_DATE),
            estado_expediente = v_estado_inicial,
            observaciones = COALESCE(NULLIF(TRIM(p_observaciones), ''), observaciones),
            actualizado_por = v_rol
        WHERE id_expediente = v_id_expediente
        RETURNING id_expediente INTO p_id_expediente_out;
    ELSE
        INSERT INTO expedientes_residencias (
            numero_control, semestre, titulo_anteproyecto, id_empresa, nombre_empresa_texto,
            asesor_externo, horario_asistencia, periodo_realizacion, fecha_entrega_fisica,
            revisado_academia, estado_expediente, observaciones, actualizado_por
        ) VALUES (
            v_ctrl, COALESCE(NULLIF(TRIM(p_semestre), ''), 'Ago-Dic 2026'), UPPER(TRIM(p_titulo_anteproyecto)),
            v_id_empresa, UPPER(TRIM(p_nombre_empresa)), NULLIF(UPPER(TRIM(p_asesor_externo)), ''),
            NULLIF(UPPER(TRIM(p_horario)), ''), NULLIF(UPPER(TRIM(p_periodo)), ''),
            COALESCE(p_fecha_entrega_fisica, CURRENT_DATE),
            'Pendiente', v_estado_inicial, NULLIF(TRIM(p_observaciones), ''), v_rol
        )
        RETURNING id_expediente INTO p_id_expediente_out;
    END IF;
END;
$$;

-- 5.2 SP 2: Actualización Completa de Expediente desde Formulario de Oficina
CREATE OR REPLACE PROCEDURE sp_actualizar_expediente_completo(
    p_id_expediente INT,
    p_numero_control VARCHAR,
    p_nombre_alumno VARCHAR,
    p_correo_institucional VARCHAR,
    p_semestre VARCHAR,
    p_especialidad VARCHAR,
    p_estado_servicio_social estado_servicio_social_enum,
    p_estado_expediente estado_expediente_enum,
    p_titulo_anteproyecto TEXT,
    p_nombre_empresa VARCHAR,
    p_asesor_externo VARCHAR,
    p_horario VARCHAR,
    p_periodo VARCHAR,
    p_fecha_entrega_fisica DATE,
    p_fecha_entrega_academia DATE,
    p_oficio_autorizacion VARCHAR,
    p_fecha_impresion DATE,
    p_fecha_notificado DATE,
    p_fecha_envio_aut_correo DATE,
    p_observaciones TEXT,
    p_actualizar_academia BOOLEAN DEFAULT FALSE,
    p_revisado_academia dictamen_academia_enum DEFAULT NULL,
    p_asesor_interno VARCHAR DEFAULT NULL,
    p_folio_academia VARCHAR DEFAULT NULL,
    p_oficio_asesor VARCHAR DEFAULT NULL,
    p_fecha_envio_asesor_correo DATE DEFAULT NULL,
    p_usuario VARCHAR DEFAULT 'GESTION_1'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol VARCHAR;
    v_id_empresa INT;
    v_id_docente INT;
    v_ctrl VARCHAR;
    v_estado_final estado_expediente_enum;
    v_asesor_final VARCHAR;
    v_oficio_pa VARCHAR;
    v_oficio_pb VARCHAR;
BEGIN
    v_rol := fn_validar_rol_activo(p_usuario, ARRAY['GESTION_1']);

    IF NOT EXISTS (SELECT 1 FROM expedientes_residencias WHERE id_expediente = p_id_expediente) THEN
        RAISE EXCEPTION 'No existe el expediente #%', p_id_expediente USING ERRCODE = 'P0001';
    END IF;

    v_ctrl := TRIM(p_numero_control);

    IF p_nombre_empresa IS NOT NULL AND TRIM(p_nombre_empresa) <> '' THEN
        INSERT INTO empresas_receptoras (nombre_empresa)
        VALUES (UPPER(TRIM(p_nombre_empresa)))
        ON CONFLICT (nombre_empresa) DO UPDATE SET activa = TRUE
        RETURNING id_empresa INTO v_id_empresa;
    END IF;

    UPDATE alumnos
    SET nombre_completo = UPPER(TRIM(p_nombre_alumno)),
        correo_institucional = COALESCE(NULLIF(LOWER(TRIM(p_correo_institucional)), ''), correo_institucional),
        especialidad = COALESCE(NULLIF(UPPER(TRIM(p_especialidad)), ''), 'INDUSTRIAL GENERAL'),
        estado_servicio_social = p_estado_servicio_social,
        actualizado_en = NOW()
    WHERE numero_control = v_ctrl;

    IF p_actualizar_academia AND p_asesor_interno IS NOT NULL AND TRIM(p_asesor_interno) <> '' THEN
        SELECT id_docente INTO v_id_docente
        FROM docentes_asesores
        WHERE UPPER(nombre_docente) = UPPER(TRIM(p_asesor_interno))
        LIMIT 1;
    END IF;

    v_oficio_pa := NULLIF(UPPER(TRIM(p_oficio_autorizacion)), '');
    v_oficio_pb := NULLIF(UPPER(TRIM(p_oficio_asesor)), '');
    v_asesor_final := CASE WHEN p_actualizar_academia THEN NULLIF(UPPER(TRIM(p_asesor_interno)), '') ELSE NULL END;

    v_estado_final := p_estado_expediente;
    IF p_estado_servicio_social = 'No Liberado (Irregular)' THEN
        v_estado_final := 'Detenido por Servicio Social';
    END IF;

    UPDATE expedientes_residencias
    SET semestre = COALESCE(NULLIF(TRIM(p_semestre), ''), semestre),
        titulo_anteproyecto = NULLIF(UPPER(TRIM(p_titulo_anteproyecto)), ''),
        id_empresa = COALESCE(v_id_empresa, id_empresa),
        nombre_empresa_texto = NULLIF(UPPER(TRIM(p_nombre_empresa)), ''),
        asesor_externo = NULLIF(UPPER(TRIM(p_asesor_externo)), ''),
        horario_asistencia = NULLIF(UPPER(TRIM(p_horario)), ''),
        periodo_realizacion = NULLIF(UPPER(TRIM(p_periodo)), ''),
        fecha_entrega_fisica = p_fecha_entrega_fisica,
        fecha_entrega_academia = p_fecha_entrega_academia,
        oficio_autorizacion = v_oficio_pa,
        fecha_impresion_oficio_aut = p_fecha_impresion,
        fecha_notificado_alumno = p_fecha_notificado,
        fecha_envio_aut_correo = p_fecha_envio_aut_correo,
        oficio_asignacion_asesor = v_oficio_pb,
        fecha_envio_asesor_correo = p_fecha_envio_asesor_correo,
        revisado_academia = CASE WHEN p_actualizar_academia AND p_revisado_academia IS NOT NULL THEN p_revisado_academia ELSE revisado_academia END,
        id_docente_asesor = CASE WHEN p_actualizar_academia THEN COALESCE(v_id_docente, id_docente_asesor) ELSE id_docente_asesor END,
        nombre_asesor_interno_texto = CASE WHEN p_actualizar_academia THEN v_asesor_final ELSE nombre_asesor_interno_texto END,
        folio_control_academia = CASE WHEN p_actualizar_academia THEN NULLIF(TRIM(p_folio_academia), '') ELSE folio_control_academia END,
        estado_expediente = CASE
            WHEN v_estado_final NOT IN ('Detenido por Servicio Social', 'Pausado / Sin Oficio', 'Caso Especial / Reasignación')
                 AND v_oficio_pa IS NOT NULL
                 AND v_oficio_pb IS NOT NULL
                 AND COALESCE(CASE WHEN p_actualizar_academia THEN v_asesor_final ELSE nombre_asesor_interno_texto END, '') <> ''
            THEN 'Expediente Completo'::estado_expediente_enum
            ELSE v_estado_final
        END,
        observaciones = NULLIF(TRIM(p_observaciones), ''),
        actualizado_por = v_rol
    WHERE id_expediente = p_id_expediente;
END;
$$;

-- 5.3 SP 3: Gestión Acepta Proyecto y Emite Oficio de Autorización (P.A) con lock transaccional
CREATE OR REPLACE PROCEDURE sp_gestion_aceptar_proyecto(
    p_id_expediente INT,
    p_oficio_autorizacion VARCHAR,
    p_fecha_entrega_academia DATE,
    p_fecha_impresion DATE,
    p_usuario VARCHAR,
    OUT p_oficio_generado VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol VARCHAR;
    v_folio VARCHAR;
    v_ss estado_servicio_social_enum;
BEGIN
    v_rol := fn_validar_rol_activo(p_usuario, ARRAY['GESTION_1']);

    SELECT a.estado_servicio_social
    INTO v_ss
    FROM expedientes_residencias e
    JOIN alumnos a ON e.numero_control = a.numero_control
    WHERE e.id_expediente = p_id_expediente;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el expediente #%', p_id_expediente USING ERRCODE = 'P0001';
    END IF;

    IF v_ss = 'No Liberado (Irregular)' THEN
        RAISE EXCEPTION 'No se puede emitir Oficio P.A: el alumno no ha liberado su Servicio Social.'
            USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('folio_PA_2026'));

    v_folio := COALESCE(NULLIF(UPPER(TRIM(p_oficio_autorizacion)), ''), fn_siguiente_folio_oficio('PA', 2026));
    p_oficio_generado := v_folio;

    UPDATE expedientes_residencias
    SET fecha_entrega_academia = COALESCE(p_fecha_entrega_academia, fecha_entrega_academia, CURRENT_DATE),
        oficio_autorizacion = v_folio,
        fecha_impresion_oficio_aut = COALESCE(p_fecha_impresion, CURRENT_DATE),
        revisado_academia = CASE WHEN revisado_academia IN ('No entregado', 'Pendiente') THEN 'Si'::dictamen_academia_enum ELSE revisado_academia END,
        estado_expediente = CASE
            WHEN COALESCE(nombre_asesor_interno_texto, '') <> '' AND COALESCE(oficio_asignacion_asesor, '') <> '' THEN 'Expediente Completo'::estado_expediente_enum
            WHEN COALESCE(nombre_asesor_interno_texto, '') <> '' THEN 'En Trámite (Falta Oficio Asesor)'::estado_expediente_enum
            ELSE 'Pendiente Asignar Asesor (Academia)'::estado_expediente_enum
        END,
        actualizado_por = v_rol
    WHERE id_expediente = p_id_expediente;
END;
$$;

-- 5.4 SP 4: Gestión Emite Oficio de Asignación de Asesor Interno (P.B)
CREATE OR REPLACE PROCEDURE sp_gestion_emitir_oficio_pb(
    p_id_expediente INT,
    p_oficio_pb VARCHAR,
    p_fecha_correo DATE,
    p_usuario VARCHAR,
    OUT p_oficio_generado VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol VARCHAR;
    v_folio_pb VARCHAR;
    v_folio_pa VARCHAR;
BEGIN
    v_rol := fn_validar_rol_activo(p_usuario, ARRAY['GESTION_1']);

    IF NOT EXISTS (SELECT 1 FROM expedientes_residencias WHERE id_expediente = p_id_expediente) THEN
        RAISE EXCEPTION 'No existe el expediente #%', p_id_expediente USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('folio_PB_2026'));

    SELECT oficio_autorizacion INTO v_folio_pa
    FROM expedientes_residencias
    WHERE id_expediente = p_id_expediente;

    IF COALESCE(v_folio_pa, '') = '' THEN
        PERFORM pg_advisory_xact_lock(hashtext('folio_PA_2026'));
        v_folio_pa := fn_siguiente_folio_oficio('PA', 2026);
    END IF;

    v_folio_pb := COALESCE(NULLIF(UPPER(TRIM(p_oficio_pb)), ''), fn_siguiente_folio_oficio('PB', 2026));
    p_oficio_generado := v_folio_pb;

    UPDATE expedientes_residencias
    SET oficio_autorizacion = COALESCE(NULLIF(oficio_autorizacion, ''), v_folio_pa),
        fecha_impresion_oficio_aut = COALESCE(fecha_impresion_oficio_aut, CURRENT_DATE),
        oficio_asignacion_asesor = v_folio_pb,
        fecha_envio_asesor_correo = COALESCE(p_fecha_correo, CURRENT_DATE),
        estado_expediente = CASE
            WHEN COALESCE(nombre_asesor_interno_texto, '') <> '' THEN 'Expediente Completo'::estado_expediente_enum
            ELSE 'Pendiente Asignar Asesor (Academia)'::estado_expediente_enum
        END,
        actualizado_por = v_rol
    WHERE id_expediente = p_id_expediente;
END;
$$;

-- 5.5 SP 5: Gestión Registra Aviso al Alumno por Correo Institucional (Outlook)
CREATE OR REPLACE PROCEDURE sp_gestion_notificar_alumno(
    p_id_expediente INT,
    p_correo_destino VARCHAR DEFAULT NULL,
    p_asunto VARCHAR DEFAULT NULL,
    p_medio_envio VARCHAR DEFAULT 'Outlook Web',
    p_fecha_notificacion DATE DEFAULT CURRENT_DATE,
    p_usuario VARCHAR DEFAULT 'GESTION_1'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol VARCHAR;
    v_ctrl VARCHAR;
    v_estado estado_expediente_enum;
    v_fecha DATE;
    v_correo VARCHAR;
    v_medio VARCHAR;
BEGIN
    v_rol := fn_validar_rol_activo(p_usuario, ARRAY['GESTION_1']);

    SELECT e.numero_control, e.estado_expediente, a.correo_institucional
    INTO v_ctrl, v_estado, v_correo
    FROM expedientes_residencias e
    JOIN alumnos a ON e.numero_control = a.numero_control
    WHERE e.id_expediente = p_id_expediente;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el expediente #%', p_id_expediente USING ERRCODE = 'P0001';
    END IF;

    v_fecha := COALESCE(p_fecha_notificacion, CURRENT_DATE);
    v_correo := COALESCE(NULLIF(LOWER(TRIM(p_correo_destino)), ''), v_correo, LOWER('l' || v_ctrl || '@cdmadero.tecnm.mx'));
    v_medio := COALESCE(NULLIF(TRIM(p_medio_envio), ''), 'Outlook Web');

    UPDATE alumnos
    SET correo_institucional = v_correo,
        actualizado_en = NOW()
    WHERE numero_control = v_ctrl;

    UPDATE expedientes_residencias
    SET fecha_notificado_alumno = v_fecha,
        fecha_envio_aut_correo = COALESCE(fecha_envio_aut_correo, v_fecha),
        correo_aviso_enviado = v_correo,
        medio_notificacion = v_medio,
        actualizado_por = v_rol
    WHERE id_expediente = p_id_expediente;

    INSERT INTO bitacora_movimientos (
        id_expediente, numero_control, usuario_responsable, tipo_operacion,
        estado_anterior, estado_nuevo, descripcion
    ) VALUES (
        p_id_expediente, v_ctrl, v_rol, 'NOTIFICACION_OUTLOOK',
        v_estado::TEXT, v_estado::TEXT,
        FORMAT('Aviso de recolección vía %s a %s (%s)%s',
            v_medio,
            v_correo,
            TO_CHAR(v_fecha, 'YYYY-MM-DD'),
            CASE WHEN NULLIF(TRIM(p_asunto), '') IS NOT NULL THEN ' · ' || TRIM(p_asunto) ELSE '' END
        )
    );
END;
$$;

-- 5.6 SP 6: Academia Asigna Docente Asesor Interno (con RBAC estricto)
CREATE OR REPLACE PROCEDURE sp_academia_asignar_asesor(
    p_id_expediente INT,
    p_id_docente INT DEFAULT NULL,
    p_nombre_docente VARCHAR DEFAULT NULL,
    p_folio_control_academia VARCHAR DEFAULT NULL,
    p_dictamen dictamen_academia_enum DEFAULT 'ASIGNADO',
    p_emitir_oficio_pb BOOLEAN DEFAULT FALSE,
    p_usuario VARCHAR DEFAULT 'ACADEMIA',
    p_correccion_admin BOOLEAN DEFAULT FALSE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol VARCHAR;
    v_doc_id INT;
    v_doc_nombre VARCHAR;
    v_folio_acad VARCHAR;
    v_oficio_pb VARCHAR;
    v_max_lot INT := 0;
BEGIN
    IF p_correccion_admin THEN
        v_rol := fn_validar_rol_activo(p_usuario, ARRAY['ACADEMIA', 'GESTION_1']);
    ELSE
        v_rol := fn_validar_rol_activo(p_usuario, ARRAY['ACADEMIA']);
    END IF;

    IF p_id_docente IS NOT NULL THEN
        SELECT id_docente, nombre_docente
        INTO v_doc_id, v_doc_nombre
        FROM docentes_asesores
        WHERE id_docente = p_id_docente;
    ELSIF COALESCE(TRIM(p_nombre_docente), '') <> '' THEN
        SELECT id_docente, nombre_docente
        INTO v_doc_id, v_doc_nombre
        FROM docentes_asesores
        WHERE UPPER(nombre_docente) = UPPER(TRIM(p_nombre_docente))
        LIMIT 1;
        IF NOT FOUND THEN
            v_doc_nombre := UPPER(TRIM(p_nombre_docente));
        END IF;
    END IF;

    IF COALESCE(v_doc_nombre, '') = '' THEN
        RAISE EXCEPTION 'Debe especificar un docente válido para asignar como Asesor Interno.'
            USING ERRCODE = 'P0001';
    END IF;

    IF COALESCE(TRIM(p_folio_control_academia), '') = '' THEN
        SELECT COALESCE(MAX((regexp_match(folio_control_academia, '26-1-(\d+)'))[1]::INT), 0)
        INTO v_max_lot
        FROM expedientes_residencias
        WHERE UPPER(COALESCE(nombre_asesor_interno_texto, '')) = UPPER(v_doc_nombre);
        v_folio_acad := '26-1-' || (v_max_lot + 1)::TEXT;
    ELSE
        v_folio_acad := TRIM(p_folio_control_academia);
    END IF;

    IF p_emitir_oficio_pb THEN
        PERFORM pg_advisory_xact_lock(hashtext('folio_PB_2026'));
        v_oficio_pb := fn_siguiente_folio_oficio('PB', 2026);
    END IF;

    UPDATE expedientes_residencias
    SET id_docente_asesor = COALESCE(v_doc_id, id_docente_asesor),
        nombre_asesor_interno_texto = UPPER(v_doc_nombre),
        folio_control_academia = v_folio_acad,
        revisado_academia = COALESCE(p_dictamen, 'ASIGNADO'::dictamen_academia_enum),
        oficio_asignacion_asesor = COALESCE(NULLIF(oficio_asignacion_asesor, ''), v_oficio_pb),
        fecha_envio_asesor_correo = CASE WHEN p_emitir_oficio_pb THEN COALESCE(fecha_envio_asesor_correo, CURRENT_DATE) ELSE fecha_envio_asesor_correo END,
        estado_expediente = CASE
            WHEN COALESCE(oficio_autorizacion, '') <> '' AND COALESCE(NULLIF(oficio_asignacion_asesor, ''), v_oficio_pb, '') <> ''
                THEN 'Expediente Completo'::estado_expediente_enum
            ELSE 'En Trámite (Falta Oficio Asesor)'::estado_expediente_enum
        END,
        actualizado_por = v_rol
    WHERE id_expediente = p_id_expediente;
END;
$$;

-- 5.7 SP 7: Control de Excepciones (Pausados, Reactivación y Validación de Servicio Social)
CREATE OR REPLACE PROCEDURE sp_cambiar_estado_excepcion(
    p_id_expediente INT,
    p_nuevo_estado estado_expediente_enum DEFAULT NULL,
    p_estado_servicio_social estado_servicio_social_enum DEFAULT NULL,
    p_motivo_observacion TEXT DEFAULT NULL,
    p_usuario VARCHAR DEFAULT 'GESTION_1'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol VARCHAR;
    v_control VARCHAR;
    v_estado_actual estado_expediente_enum;
    v_ss_actual estado_servicio_social_enum;
    v_nuevo_estado_res estado_expediente_enum;
    v_ss_final estado_servicio_social_enum;
    v_tiene_proy BOOLEAN;
    v_tiene_asesor BOOLEAN;
    v_tiene_pb BOOLEAN;
BEGIN
    v_rol := fn_validar_rol_activo(p_usuario, ARRAY['GESTION_1']);

    SELECT e.numero_control, e.estado_expediente, a.estado_servicio_social,
           COALESCE(e.titulo_anteproyecto, '') <> '',
           COALESCE(e.nombre_asesor_interno_texto, '') <> '',
           COALESCE(e.oficio_asignacion_asesor, '') <> ''
    INTO v_control, v_estado_actual, v_ss_actual, v_tiene_proy, v_tiene_asesor, v_tiene_pb
    FROM expedientes_residencias e
    JOIN alumnos a ON e.numero_control = a.numero_control
    WHERE e.id_expediente = p_id_expediente;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el expediente #%', p_id_expediente USING ERRCODE = 'P0001';
    END IF;

    v_ss_final := COALESCE(p_estado_servicio_social, v_ss_actual);

    IF p_estado_servicio_social IS NOT NULL THEN
        UPDATE alumnos
        SET estado_servicio_social = p_estado_servicio_social,
            actualizado_en = NOW()
        WHERE numero_control = v_control;
    END IF;

    IF p_nuevo_estado IS NOT NULL THEN
        v_nuevo_estado_res := p_nuevo_estado;
    ELSIF v_ss_final = 'No Liberado (Irregular)' THEN
        v_nuevo_estado_res := 'Detenido por Servicio Social';
    ELSIF v_estado_actual = 'Detenido por Servicio Social' AND v_ss_final = 'Liberado' THEN
        IF v_tiene_asesor AND v_tiene_pb THEN
            v_nuevo_estado_res := 'Expediente Completo';
        ELSE
            v_nuevo_estado_res := 'En Revisión por Academia';
        END IF;
    ELSE
        v_nuevo_estado_res := v_estado_actual;
    END IF;

    UPDATE expedientes_residencias
    SET estado_expediente = v_nuevo_estado_res,
        observaciones = COALESCE(NULLIF(TRIM(p_motivo_observacion), ''), observaciones),
        actualizado_por = v_rol
    WHERE id_expediente = p_id_expediente;

    -- Si solo cambió Servicio Social sin cambiar estado_expediente, registrar en bitácora manualmente
    IF v_estado_actual = v_nuevo_estado_res AND v_ss_actual IS DISTINCT FROM v_ss_final THEN
        INSERT INTO bitacora_movimientos (
            id_expediente, numero_control, usuario_responsable, tipo_operacion,
            estado_anterior, estado_nuevo, descripcion
        ) VALUES (
            p_id_expediente, v_control, v_rol, 'ACTUALIZACION_SERVICIO_SOCIAL',
            v_ss_actual::TEXT, v_ss_final::TEXT,
            COALESCE(NULLIF(TRIM(p_motivo_observacion), ''), 'Actualización de estatus de Servicio Social')
        );
    END IF;
END;
$$;

-- ============================================================================
-- 6. PERMISOS EXCLUSIVOS DE EJECUCIÓN PARA app_residencias_user
-- ============================================================================
REVOKE ALL ON FUNCTION fn_validar_rol_activo(VARCHAR, TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_siguiente_folio_oficio(VARCHAR, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_api_obtener_estado_inicial() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_api_obtener_expediente(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_api_obtener_carga_docentes() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_api_obtener_bitacora(VARCHAR, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_buscar_expedientes(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) FROM PUBLIC;

REVOKE ALL ON PROCEDURE sp_registrar_solicitud_anteproyecto(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, DATE, TEXT, VARCHAR, INT) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_actualizar_expediente_completo(INT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, estado_expediente_enum, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, DATE, VARCHAR, DATE, DATE, DATE, TEXT, BOOLEAN, dictamen_academia_enum, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_gestion_aceptar_proyecto(INT, VARCHAR, DATE, DATE, VARCHAR, VARCHAR) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_gestion_emitir_oficio_pb(INT, VARCHAR, DATE, VARCHAR, VARCHAR) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_gestion_notificar_alumno(INT, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_academia_asignar_asesor(INT, INT, VARCHAR, VARCHAR, dictamen_academia_enum, BOOLEAN, VARCHAR, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_cambiar_estado_excepcion(INT, estado_expediente_enum, estado_servicio_social_enum, TEXT, VARCHAR) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_siguiente_folio_oficio(VARCHAR, INT) TO app_residencias_user;
GRANT EXECUTE ON FUNCTION fn_api_obtener_estado_inicial() TO app_residencias_user;
GRANT EXECUTE ON FUNCTION fn_api_obtener_expediente(INT) TO app_residencias_user;
GRANT EXECUTE ON FUNCTION fn_api_obtener_carga_docentes() TO app_residencias_user;
GRANT EXECUTE ON FUNCTION fn_api_obtener_bitacora(VARCHAR, INT) TO app_residencias_user;
GRANT EXECUTE ON FUNCTION fn_buscar_expedientes(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO app_residencias_user;

GRANT EXECUTE ON PROCEDURE sp_registrar_solicitud_anteproyecto(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, DATE, TEXT, VARCHAR, INT) TO app_residencias_user;
GRANT EXECUTE ON PROCEDURE sp_actualizar_expediente_completo(INT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, estado_servicio_social_enum, estado_expediente_enum, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, DATE, VARCHAR, DATE, DATE, DATE, TEXT, BOOLEAN, dictamen_academia_enum, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR) TO app_residencias_user;
GRANT EXECUTE ON PROCEDURE sp_gestion_aceptar_proyecto(INT, VARCHAR, DATE, DATE, VARCHAR, VARCHAR) TO app_residencias_user;
GRANT EXECUTE ON PROCEDURE sp_gestion_emitir_oficio_pb(INT, VARCHAR, DATE, VARCHAR, VARCHAR) TO app_residencias_user;
GRANT EXECUTE ON PROCEDURE sp_gestion_notificar_alumno(INT, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR) TO app_residencias_user;
GRANT EXECUTE ON PROCEDURE sp_academia_asignar_asesor(INT, INT, VARCHAR, VARCHAR, dictamen_academia_enum, BOOLEAN, VARCHAR, BOOLEAN) TO app_residencias_user;
GRANT EXECUTE ON PROCEDURE sp_cambiar_estado_excepcion(INT, estado_expediente_enum, estado_servicio_social_enum, TEXT, VARCHAR) TO app_residencias_user;
