-- ============================================================================
-- SISTEMA DE CONTROL DE PROCESOS DE RESIDENCIAS PROFESIONALES (ING. INDUSTRIAL)
-- Base de Datos Relacional PostgreSQL 16 + Procedimientos Almacenados + Triggers
-- Compatible con: PostgreSQL 14, 15, 16+ y pgAdmin 4
-- ============================================================================

SET client_encoding = 'UTF8';

-- 1. EXTENSIONES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. LIMPIEZA PREVIA (IDEMPOTENTE PARA RE-EJECUCIÓN EN PGADMIN 4)
DROP VIEW IF EXISTS v_expedientes_completos CASCADE;
DROP VIEW IF EXISTS v_carga_asesores_internos CASCADE;
DROP VIEW IF EXISTS v_auditoria_sii_y_excepciones CASCADE;
DROP VIEW IF EXISTS v_kpis_dashboard CASCADE;

DROP TABLE IF EXISTS bitacora_movimientos CASCADE;
DROP TABLE IF EXISTS expedientes_residencias CASCADE;
DROP TABLE IF EXISTS alumnos CASCADE;
DROP TABLE IF EXISTS empresas_receptoras CASCADE;
DROP TABLE IF EXISTS docentes_asesores CASCADE;
DROP TABLE IF EXISTS usuarios_sistema CASCADE;

DROP TYPE IF EXISTS rol_sistema_enum CASCADE;
DROP TYPE IF EXISTS estado_servicio_social_enum CASCADE;
DROP TYPE IF EXISTS estado_expediente_enum CASCADE;
DROP TYPE IF EXISTS dictamen_academia_enum CASCADE;
DROP TYPE IF EXISTS jornada_docente_enum CASCADE;

-- ============================================================================
-- 3. TIPOS ENUMERADOS (ENUMS DEL DOMINIO DE RESIDENCIAS INDUSTRIAL)
-- ============================================================================

CREATE TYPE rol_sistema_enum AS ENUM (
    'GESTION_1',
    'GESTION_2',
    'ACADEMIA'
);

CREATE TYPE estado_servicio_social_enum AS ENUM (
    'Liberado',
    'Por verificar',
    'Por verificar (Posible falta de S.S.)',
    'No Liberado (Irregular)'
);

CREATE TYPE estado_expediente_enum AS ENUM (
    'Inscrito en SII sin Anteproyecto',
    'En Revisión por Academia',
    'Pendiente Asignar Asesor (Academia)',
    'En Trámite (Falta Oficio Asesor)',
    'Expediente Completo',
    'Pausado / Sin Oficio',
    'Detenido por Servicio Social',
    'Caso Especial / Reasignación'
);

CREATE TYPE dictamen_academia_enum AS ENUM (
    'No entregado',
    'Pendiente',
    'Si',
    'SI',
    'ASIGNADO',
    'NO'
);

CREATE TYPE jornada_docente_enum AS ENUM (
    '40 hrs',
    '30 hrs',
    '20 hrs',
    'Por horas'
);

-- ============================================================================
-- 4. TABLAS RELACIONALES PRINCIPALES
-- ============================================================================

-- 4.1 Usuarios del Sistema (Exclusivo: 2 Usuarios de Gestión y 1 de Academia)
CREATE TABLE usuarios_sistema (
    id_usuario SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    nombre_mostrar VARCHAR(120) NOT NULL,
    rol rol_sistema_enum NOT NULL,
    correo VARCHAR(120) UNIQUE NOT NULL,
    responsabilidad TEXT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE usuarios_sistema IS 'Usuarios administrativos del sistema (2 de Gestión y 1 de Academia). Los alumnos NO son usuarios del sistema.';

-- 4.2 Catálogo de Docentes / Asesores Internos (Hoja Maestros de 26-1 ASIGNACION DE ASESORES.xlsx)
CREATE TABLE docentes_asesores (
    id_docente SERIAL PRIMARY KEY,
    nombre_docente VARCHAR(160) UNIQUE NOT NULL,
    jornada jornada_docente_enum NOT NULL DEFAULT '40 hrs',
    beca VARCHAR(40) NOT NULL DEFAULT 'Ninguna',
    historico_proy_ene_jun INT NOT NULL DEFAULT 0,
    historico_interno_ene_jun INT NOT NULL DEFAULT 0,
    historico_proy_ago_dic INT NOT NULL DEFAULT 0,
    historico_interno_ago_dic INT NOT NULL DEFAULT 0,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE docentes_asesores IS 'Plantilla de 42 docentes de Ingeniería Industrial para asignación de Asesor Interno por Academia.';

-- 4.3 Catálogo de Empresas Receptoras
CREATE TABLE empresas_receptoras (
    id_empresa SERIAL PRIMARY KEY,
    nombre_empresa VARCHAR(250) UNIQUE NOT NULL,
    sector_industrial VARCHAR(100) DEFAULT 'Industrial / Servicios',
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE empresas_receptoras IS 'Directorio de empresas e instituciones donde los residentes desarrollan sus proyectos.';

-- 4.4 Padrón de Alumnos y Cruce SII + Servicio Social
CREATE TABLE alumnos (
    numero_control VARCHAR(20) PRIMARY KEY,
    nombre_completo VARCHAR(180) NOT NULL,
    especialidad VARCHAR(100) NOT NULL DEFAULT 'INDUSTRIAL GENERAL',
    en_sii_08_sep BOOLEAN NOT NULL DEFAULT FALSE,
    en_sii_18_sep BOOLEAN NOT NULL DEFAULT FALSE,
    estado_servicio_social estado_servicio_social_enum NOT NULL DEFAULT 'Por verificar',
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE alumnos IS 'Padrón de estudiantes de Ingeniería Industrial con banderas de aparición en el SII y validación de Servicio Social.';

-- 4.5 Tabla Central: Expedientes y Solicitudes de Residencias Profesionales
CREATE TABLE expedientes_residencias (
    id_expediente SERIAL PRIMARY KEY,
    numero_control VARCHAR(20) NOT NULL REFERENCES alumnos(numero_control) ON UPDATE CASCADE ON DELETE RESTRICT,
    semestre VARCHAR(40) NOT NULL DEFAULT 'Ago-Dic 2026',
    titulo_anteproyecto TEXT,
    id_empresa INT REFERENCES empresas_receptoras(id_empresa) ON UPDATE CASCADE ON DELETE SET NULL,
    nombre_empresa_texto VARCHAR(250),
    asesor_externo VARCHAR(180),
    horario_asistencia VARCHAR(120),
    periodo_realizacion VARCHAR(160),

    -- Etapa 1 y 2: Recepción Física de Hojas y Aceptación por Gestión
    fecha_entrega_fisica DATE,
    nota_entrega_fisica VARCHAR(80),
    fecha_entrega_academia DATE,
    oficio_autorizacion VARCHAR(50),
    fecha_impresion_oficio_aut DATE,
    fecha_notificado_alumno DATE,
    fecha_envio_aut_correo DATE,

    -- Etapa 3: Dictamen y Asignación de Asesor Interno por Academia
    revisado_academia dictamen_academia_enum NOT NULL DEFAULT 'Pendiente',
    id_docente_asesor INT REFERENCES docentes_asesores(id_docente) ON UPDATE CASCADE ON DELETE SET NULL,
    nombre_asesor_interno_texto VARCHAR(180),
    folio_control_academia VARCHAR(40),
    oficio_asignacion_asesor VARCHAR(50),
    fecha_envio_asesor_correo DATE,

    -- Estado General del Proceso y Excepciones (Pausados / S.S. / SII)
    estado_expediente estado_expediente_enum NOT NULL DEFAULT 'En Revisión por Academia',
    observaciones TEXT,
    actualizado_por VARCHAR(50) DEFAULT 'GESTION_1',
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE expedientes_residencias IS 'Tabla maestra del flujo de 3 etapas: 1) Alumno entrega hojas de anteproyecto, 2) Gestión acepta y emite Oficio P.A, 3) Academia asigna asesor interno y se emite Oficio P.B.';

CREATE INDEX idx_exp_control ON expedientes_residencias(numero_control);
CREATE INDEX idx_exp_semestre ON expedientes_residencias(semestre);
CREATE INDEX idx_exp_estado ON expedientes_residencias(estado_expediente);
CREATE INDEX idx_exp_docente ON expedientes_residencias(id_docente_asesor);
CREATE INDEX idx_exp_oficio_pa ON expedientes_residencias(oficio_autorizacion);
CREATE INDEX idx_exp_oficio_pb ON expedientes_residencias(oficio_asignacion_asesor);

-- 4.6 Bitácora Automática de Auditoría (Kardex de Movimientos de Gestión y Academia)
CREATE TABLE bitacora_movimientos (
    id_movimiento BIGSERIAL PRIMARY KEY,
    id_expediente INT REFERENCES expedientes_residencias(id_expediente) ON DELETE CASCADE,
    numero_control VARCHAR(20),
    usuario_responsable VARCHAR(50) NOT NULL DEFAULT 'SISTEMA',
    tipo_operacion VARCHAR(60) NOT NULL,
    estado_anterior VARCHAR(80),
    estado_nuevo VARCHAR(80),
    descripcion TEXT NOT NULL,
    fecha_movimiento TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE bitacora_movimientos IS 'Historial auditable de cambios de estado, asignaciones de asesor, pausas y bloqueos por Servicio Social.';

-- ============================================================================
-- 5. FUNCIONES, TRIGGERS Y PROCEDIMIENTOS ALMACENADOS (STORED PROCEDURES)
-- ============================================================================

-- 5.1 Función Generadora Automática del Siguiente Folio de Oficio (P.Axxx/2026 o P.Bxxx/2026)
CREATE OR REPLACE FUNCTION fn_siguiente_folio_oficio(
    p_tipo_oficio VARCHAR, -- 'PA' (Autorización) o 'PB' (Asignación Asesor)
    p_anio INT DEFAULT 2026
)
RETURNS VARCHAR AS $$
DECLARE
    v_prefijo VARCHAR;
    v_max_num INT := 0;
BEGIN
    v_prefijo := CASE WHEN UPPER(p_tipo_oficio) = 'PA' THEN 'P.A' ELSE 'P.B' END;

    IF UPPER(p_tipo_oficio) = 'PA' THEN
        SELECT COALESCE(MAX(( regexp_match(oficio_autorizacion, 'P\.A(\d+)/' || p_anio::TEXT) )[1]::INT), 0)
        INTO v_max_num
        FROM expedientes_residencias
        WHERE oficio_autorizacion ~ ('^P\.A\d+/' || p_anio::TEXT);
    ELSE
        SELECT COALESCE(MAX(( regexp_match(oficio_asignacion_asesor, 'P\.B(\d+)/' || p_anio::TEXT) )[1]::INT), 0)
        INTO v_max_num
        FROM expedientes_residencias
        WHERE oficio_asignacion_asesor ~ ('^P\.B\d+/' || p_anio::TEXT);
    END IF;

    RETURN v_prefijo || LPAD((v_max_num + 1)::TEXT, 3, '0') || '/' || p_anio::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_siguiente_folio_oficio IS 'Calcula automáticamente el siguiente número de oficio consecutivo P.Axxx/AAAA o P.Bxxx/AAAA.';

-- 5.2 Triggers de Reglas de Negocio: Validación (BEFORE) y Auditoría en Bitácora (AFTER)
CREATE OR REPLACE FUNCTION fn_trg_validar_expediente()
RETURNS TRIGGER AS $$
DECLARE
    v_ss estado_servicio_social_enum;
BEGIN
    NEW.actualizado_en := NOW();

    -- Consultar si el alumno tiene el Servicio Social No Liberado
    SELECT estado_servicio_social INTO v_ss
    FROM alumnos
    WHERE numero_control = NEW.numero_control;

    -- Regla de negocio: Si el Servicio Social está marcado como No Liberado (Irregular),
    -- el expediente pasa automáticamente a Detenido por Servicio Social
    IF v_ss = 'No Liberado (Irregular)' AND NEW.estado_expediente NOT IN ('Detenido por Servicio Social', 'Pausado / Sin Oficio') THEN
        NEW.estado_expediente := 'Detenido por Servicio Social';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_01_validar_expediente
BEFORE INSERT OR UPDATE ON expedientes_residencias
FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_expediente();

CREATE OR REPLACE FUNCTION fn_trg_auditar_expediente()
RETURNS TRIGGER AS $$
BEGIN
    -- Registrar automáticamente en la bitácora si se dio de alta o cambió el estado/asesor/oficios
    IF TG_OP = 'INSERT' THEN
        INSERT INTO bitacora_movimientos (
            id_expediente, numero_control, usuario_responsable, tipo_operacion,
            estado_anterior, estado_nuevo, descripcion
        ) VALUES (
            NEW.id_expediente, NEW.numero_control, COALESCE(NEW.actualizado_por, 'GESTION_1'),
            'ALTA_EXPEDIENTE', NULL, NEW.estado_expediente::TEXT,
            'Registro inicial de expediente. Proyecto: ' || COALESCE(NEW.titulo_anteproyecto, 'Sin anteproyecto físico')
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.estado_expediente IS DISTINCT FROM NEW.estado_expediente
           OR OLD.nombre_asesor_interno_texto IS DISTINCT FROM NEW.nombre_asesor_interno_texto
           OR OLD.oficio_autorizacion IS DISTINCT FROM NEW.oficio_autorizacion
           OR OLD.oficio_asignacion_asesor IS DISTINCT FROM NEW.oficio_asignacion_asesor THEN

            INSERT INTO bitacora_movimientos (
                id_expediente, numero_control, usuario_responsable, tipo_operacion,
                estado_anterior, estado_nuevo, descripcion
            ) VALUES (
                NEW.id_expediente, NEW.numero_control, COALESCE(NEW.actualizado_por, 'GESTION_1'),
                'ACTUALIZACION_FLUJO', OLD.estado_expediente::TEXT, NEW.estado_expediente::TEXT,
                FORMAT('Oficio P.A: %s -> %s | Asesor: %s -> %s | Oficio P.B: %s -> %s',
                    COALESCE(OLD.oficio_autorizacion, '-'), COALESCE(NEW.oficio_autorizacion, '-'),
                    COALESCE(OLD.nombre_asesor_interno_texto, '-'), COALESCE(NEW.nombre_asesor_interno_texto, '-'),
                    COALESCE(OLD.oficio_asignacion_asesor, '-'), COALESCE(NEW.oficio_asignacion_asesor, '-')
                )
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_02_auditar_expediente
AFTER INSERT OR UPDATE ON expedientes_residencias
FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar_expediente();

-- 5.3 PROCEDIMIENTO ALMACENADO 1 (ETAPA 1): Recepción de Solicitud Física en Ventanilla (Hojas Impresas)
CREATE OR REPLACE PROCEDURE sp_registrar_solicitud_anteproyecto(
    p_numero_control VARCHAR,
    p_nombre_alumno VARCHAR,
    p_semestre VARCHAR,
    p_especialidad VARCHAR,
    p_titulo_anteproyecto TEXT,
    p_nombre_empresa VARCHAR,
    p_asesor_externo VARCHAR,
    p_horario VARCHAR,
    p_periodo VARCHAR,
    p_estado_servicio_social estado_servicio_social_enum,
    p_fecha_entrega_fisica DATE DEFAULT CURRENT_DATE,
    p_observaciones TEXT DEFAULT NULL,
    p_usuario VARCHAR DEFAULT 'GESTION_1'
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_empresa INT;
    v_id_expediente INT;
    v_estado_inicial estado_expediente_enum;
BEGIN
    -- 1. Asegurar empresa receptora en catálogo
    IF p_nombre_empresa IS NOT NULL AND TRIM(p_nombre_empresa) <> '' THEN
        INSERT INTO empresas_receptoras (nombre_empresa)
        VALUES (UPPER(TRIM(p_nombre_empresa)))
        ON CONFLICT (nombre_empresa) DO UPDATE SET activa = TRUE
        RETURNING id_empresa INTO v_id_empresa;
    END IF;

    -- 2. Insertar o actualizar datos del alumno y su estatus de Servicio Social
    INSERT INTO alumnos (
        numero_control, nombre_completo, especialidad, estado_servicio_social, actualizado_en
    ) VALUES (
        TRIM(p_numero_control), UPPER(TRIM(p_nombre_alumno)),
        COALESCE(NULLIF(UPPER(TRIM(p_especialidad)), ''), 'INDUSTRIAL GENERAL'),
        p_estado_servicio_social, NOW()
    )
    ON CONFLICT (numero_control) DO UPDATE
    SET nombre_completo = EXCLUDED.nombre_completo,
        especialidad = EXCLUDED.especialidad,
        estado_servicio_social = EXCLUDED.estado_servicio_social,
        actualizado_en = NOW();

    -- 3. Determinar estado inicial según validación de Servicio Social
    IF p_estado_servicio_social = 'No Liberado (Irregular)' THEN
        v_estado_inicial := 'Detenido por Servicio Social';
    ELSE
        v_estado_inicial := 'En Revisión por Academia';
    END IF;

    -- 4. Verificar si el alumno ya tenía un registro previo (ej. estaba en SII sin anteproyecto)
    SELECT id_expediente INTO v_id_expediente
    FROM expedientes_residencias
    WHERE numero_control = TRIM(p_numero_control)
    ORDER BY id_expediente DESC
    LIMIT 1;

    IF v_id_expediente IS NOT NULL THEN
        UPDATE expedientes_residencias
        SET semestre = p_semestre,
            titulo_anteproyecto = UPPER(TRIM(p_titulo_anteproyecto)),
            id_empresa = v_id_empresa,
            nombre_empresa_texto = UPPER(TRIM(p_nombre_empresa)),
            asesor_externo = UPPER(TRIM(p_asesor_externo)),
            horario_asistencia = UPPER(TRIM(p_horario)),
            periodo_realizacion = UPPER(TRIM(p_periodo)),
            fecha_entrega_fisica = COALESCE(p_fecha_entrega_fisica, CURRENT_DATE),
            estado_expediente = v_estado_inicial,
            observaciones = COALESCE(p_observaciones, observaciones),
            actualizado_por = p_usuario
        WHERE id_expediente = v_id_expediente;
    ELSE
        INSERT INTO expedientes_residencias (
            numero_control, semestre, titulo_anteproyecto, id_empresa, nombre_empresa_texto,
            asesor_externo, horario_asistencia, periodo_realizacion, fecha_entrega_fisica,
            revisado_academia, estado_expediente, observaciones, actualizado_por
        ) VALUES (
            TRIM(p_numero_control), p_semestre, UPPER(TRIM(p_titulo_anteproyecto)),
            v_id_empresa, UPPER(TRIM(p_nombre_empresa)), UPPER(TRIM(p_asesor_externo)),
            UPPER(TRIM(p_horario)), UPPER(TRIM(p_periodo)), COALESCE(p_fecha_entrega_fisica, CURRENT_DATE),
            'Pendiente', v_estado_inicial, p_observaciones, p_usuario
        );
    END IF;
END;
$$;

COMMENT ON PROCEDURE sp_registrar_solicitud_anteproyecto IS 'Etapa 1: Registra la entrega de hojas impresas del alumno en ventanilla de Gestión y valida su Servicio Social.';

-- 5.4 PROCEDIMIENTO ALMACENADO 2 (ETAPA 2): Gestión Acepta Proyecto y Emite Oficio de Autorización (P.A)
CREATE OR REPLACE PROCEDURE sp_gestion_aceptar_proyecto(
    p_id_expediente INT,
    p_oficio_autorizacion VARCHAR DEFAULT NULL,
    p_fecha_entrega_academia DATE DEFAULT CURRENT_DATE,
    p_fecha_impresion DATE DEFAULT CURRENT_DATE,
    p_usuario VARCHAR DEFAULT 'GESTION_1'
)
LANGUAGE plpgsql AS $$
DECLARE
    v_folio VARCHAR;
BEGIN
    v_folio := COALESCE(NULLIF(TRIM(p_oficio_autorizacion), ''), fn_siguiente_folio_oficio('PA', 2026));

    UPDATE expedientes_residencias
    SET fecha_entrega_academia = COALESCE(p_fecha_entrega_academia, fecha_entrega_academia, CURRENT_DATE),
        oficio_autorizacion = v_folio,
        fecha_impresion_oficio_aut = COALESCE(p_fecha_impresion, CURRENT_DATE),
        revisado_academia = CASE WHEN revisado_academia IN ('No entregado', 'Pendiente') THEN 'Si'::dictamen_academia_enum ELSE revisado_academia END,
        estado_expediente = CASE
            WHEN nombre_asesor_interno_texto IS NOT NULL AND oficio_asignacion_asesor IS NOT NULL THEN 'Expediente Completo'::estado_expediente_enum
            WHEN nombre_asesor_interno_texto IS NOT NULL THEN 'En Trámite (Falta Oficio Asesor)'::estado_expediente_enum
            ELSE 'Pendiente Asignar Asesor (Academia)'::estado_expediente_enum
        END,
        actualizado_por = p_usuario
    WHERE id_expediente = p_id_expediente;
END;
$$;

COMMENT ON PROCEDURE sp_gestion_aceptar_proyecto IS 'Etapa 2: Gestión autoriza el proyecto, registra el Oficio P.Axxx/2026 (o lo autogenera) y lo turna a asignación de asesor.';

-- 5.5 PROCEDIMIENTO ALMACENADO 3 (ETAPA 3): Academia Asigna Docente Asesor Interno
CREATE OR REPLACE PROCEDURE sp_academia_asignar_asesor(
    p_id_expediente INT,
    p_id_docente INT,
    p_folio_control_academia VARCHAR DEFAULT NULL,
    p_emitir_oficio_pb BOOLEAN DEFAULT TRUE,
    p_usuario VARCHAR DEFAULT 'ACADEMIA'
)
LANGUAGE plpgsql AS $$
DECLARE
    v_nombre_docente VARCHAR;
    v_oficio_pb VARCHAR;
BEGIN
    SELECT nombre_docente INTO v_nombre_docente
    FROM docentes_asesores
    WHERE id_docente = p_id_docente;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el docente con ID %', p_id_docente;
    END IF;

    IF p_emitir_oficio_pb THEN
        v_oficio_pb := fn_siguiente_folio_oficio('PB', 2026);
    END IF;

    UPDATE expedientes_residencias
    SET id_docente_asesor = p_id_docente,
        nombre_asesor_interno_texto = UPPER(v_nombre_docente),
        folio_control_academia = COALESCE(p_folio_control_academia, folio_control_academia),
        revisado_academia = 'ASIGNADO',
        oficio_asignacion_asesor = COALESCE(oficio_asignacion_asesor, v_oficio_pb),
        fecha_envio_asesor_correo = CASE WHEN p_emitir_oficio_pb THEN CURRENT_DATE ELSE fecha_envio_asesor_correo END,
        estado_expediente = CASE
            WHEN oficio_autorizacion IS NOT NULL AND (oficio_asignacion_asesor IS NOT NULL OR v_oficio_pb IS NOT NULL)
                THEN 'Expediente Completo'::estado_expediente_enum
            ELSE 'En Trámite (Falta Oficio Asesor)'::estado_expediente_enum
        END,
        actualizado_por = p_usuario
    WHERE id_expediente = p_id_expediente;
END;
$$;

COMMENT ON PROCEDURE sp_academia_asignar_asesor IS 'Etapa 3: Academia asigna un docente de Industrial como Asesor Interno y opcionalmente genera el Oficio P.Bxxx/2026.';

-- 5.6 PROCEDIMIENTO ALMACENADO 4: Control de Excepciones (Pausar Trámite / Bloquear por Servicio Social)
CREATE OR REPLACE PROCEDURE sp_cambiar_estado_excepcion(
    p_id_expediente INT,
    p_nuevo_estado estado_expediente_enum,
    p_estado_servicio_social estado_servicio_social_enum,
    p_motivo_observacion TEXT,
    p_usuario VARCHAR DEFAULT 'GESTION_1'
)
LANGUAGE plpgsql AS $$
DECLARE
    v_control VARCHAR;
BEGIN
    SELECT numero_control INTO v_control
    FROM expedientes_residencias
    WHERE id_expediente = p_id_expediente;

    IF v_control IS NOT NULL AND p_estado_servicio_social IS NOT NULL THEN
        UPDATE alumnos
        SET estado_servicio_social = p_estado_servicio_social,
            actualizado_en = NOW()
        WHERE numero_control = v_control;
    END IF;

    UPDATE expedientes_residencias
    SET estado_expediente = p_nuevo_estado,
        observaciones = COALESCE(p_motivo_observacion, observaciones),
        actualizado_por = p_usuario
    WHERE id_expediente = p_id_expediente;
END;
$$;

COMMENT ON PROCEDURE sp_cambiar_estado_excepcion IS 'Marca un expediente como Pausado/Abandonado por el alumno o Detenido por falta de Servicio Social.';

-- 5.7 FUNCIÓN DE CONSULTA UNIVERSAL MULTICAMPO (Para buscador instantáneo o reportes en pgAdmin 4)
CREATE OR REPLACE FUNCTION fn_buscar_expedientes(
    p_texto_busqueda VARCHAR DEFAULT NULL,
    p_semestre VARCHAR DEFAULT NULL,
    p_estado VARCHAR DEFAULT NULL,
    p_servicio_social VARCHAR DEFAULT NULL,
    p_asesor_interno VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id_expediente INT,
    numero_control VARCHAR,
    nombre_alumno VARCHAR,
    semestre VARCHAR,
    especialidad VARCHAR,
    estado_servicio_social VARCHAR,
    estado_expediente VARCHAR,
    titulo_anteproyecto TEXT,
    empresa VARCHAR,
    oficio_autorizacion VARCHAR,
    asesor_interno VARCHAR,
    oficio_asignacion_asesor VARCHAR,
    folio_academia VARCHAR,
    fecha_entrega_fisica DATE,
    en_sii_18_sep BOOLEAN,
    observaciones TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id_expediente,
        e.numero_control,
        a.nombre_completo AS nombre_alumno,
        e.semestre,
        a.especialidad,
        a.estado_servicio_social::VARCHAR,
        e.estado_expediente::VARCHAR,
        e.titulo_anteproyecto,
        e.nombre_empresa_texto AS empresa,
        e.oficio_autorizacion,
        e.nombre_asesor_interno_texto AS asesor_interno,
        e.oficio_asignacion_asesor,
        e.folio_control_academia AS folio_academia,
        e.fecha_entrega_fisica,
        a.en_sii_18_sep,
        e.observaciones
    FROM expedientes_residencias e
    JOIN alumnos a ON e.numero_control = a.numero_control
    WHERE
        (p_semestre IS NULL OR p_semestre = 'ALL' OR e.semestre = p_semestre)
        AND (p_estado IS NULL OR p_estado = 'ALL' OR e.estado_expediente::TEXT = p_estado)
        AND (p_servicio_social IS NULL OR p_servicio_social = 'ALL' OR a.estado_servicio_social::TEXT = p_servicio_social)
        AND (p_asesor_interno IS NULL OR p_asesor_interno = 'ALL' OR UPPER(COALESCE(e.nombre_asesor_interno_texto, '')) LIKE '%' || UPPER(p_asesor_interno) || '%')
        AND (
            p_texto_busqueda IS NULL OR TRIM(p_texto_busqueda) = '' OR
            CONCAT_WS(' ',
                e.numero_control, a.nombre_completo, e.titulo_anteproyecto,
                e.nombre_empresa_texto, e.nombre_asesor_interno_texto,
                e.asesor_externo, e.oficio_autorizacion, e.oficio_asignacion_asesor,
                e.folio_control_academia, e.observaciones
            ) ILIKE '%' || TRIM(p_texto_busqueda) || '%'
        )
    ORDER BY e.id_expediente ASC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_buscar_expedientes IS 'Buscador multicampo que reemplaza los filtros manuales de Excel.';

-- ============================================================================
-- 6. VISTAS ANALÍTICAS PARA CONSULTA DIRECTA EN PGADMIN 4
-- ============================================================================

-- Vista 1: Sábana Completa de Expedientes (Equivalente enriquecido a Protocolos a Academia)
CREATE OR REPLACE VIEW v_expedientes_completos AS
SELECT
    e.id_expediente,
    e.numero_control,
    a.nombre_completo AS alumno,
    e.semestre,
    a.especialidad,
    a.estado_servicio_social,
    e.estado_expediente,
    e.titulo_anteproyecto,
    COALESCE(emp.nombre_empresa, e.nombre_empresa_texto) AS empresa,
    e.horario_asistencia,
    e.periodo_realizacion,
    e.fecha_entrega_fisica,
    e.fecha_entrega_academia,
    e.revisado_academia,
    e.oficio_autorizacion,
    e.fecha_impresion_oficio_aut,
    e.fecha_notificado_alumno,
    e.fecha_envio_aut_correo,
    COALESCE(d.nombre_docente, e.nombre_asesor_interno_texto) AS asesor_interno,
    e.folio_control_academia,
    e.oficio_asignacion_asesor,
    e.fecha_envio_asesor_correo,
    e.asesor_externo,
    a.en_sii_08_sep,
    a.en_sii_18_sep,
    e.observaciones
FROM expedientes_residencias e
JOIN alumnos a ON e.numero_control = a.numero_control
LEFT JOIN empresas_receptoras emp ON e.id_empresa = emp.id_empresa
LEFT JOIN docentes_asesores d ON e.id_docente_asesor = d.id_docente
ORDER BY e.id_expediente ASC;

-- Vista 2: Carga de Asesores Internos en Tiempo Real (Hoja Maestros + Residentes Activos)
CREATE OR REPLACE VIEW v_carga_asesores_internos AS
SELECT
    d.id_docente,
    d.nombre_docente,
    d.jornada,
    d.beca,
    d.historico_proy_ene_jun,
    d.historico_interno_ene_jun,
    d.historico_proy_ago_dic,
    d.historico_interno_ago_dic,
    COUNT(e.id_expediente) AS residentes_asignados_en_bd,
    STRING_AGG(a.nombre_completo || ' (' || e.numero_control || ')', ', ' ORDER BY a.nombre_completo) AS lista_residentes
FROM docentes_asesores d
LEFT JOIN expedientes_residencias e ON d.id_docente = e.id_docente_asesor
LEFT JOIN alumnos a ON e.numero_control = a.numero_control
GROUP BY d.id_docente, d.nombre_docente, d.jornada, d.beca,
         d.historico_proy_ene_jun, d.historico_interno_ene_jun,
         d.historico_proy_ago_dic, d.historico_interno_ago_dic
ORDER BY residentes_asignados_en_bd DESC, d.nombre_docente ASC;

-- Vista 3: Auditoría de Irregularidades (SII sin Anteproyecto, Servicio Social Pendiente y Trámites Pausados)
CREATE OR REPLACE VIEW v_auditoria_sii_y_excepciones AS
SELECT
    e.id_expediente,
    e.numero_control,
    a.nombre_completo AS alumno,
    e.semestre,
    a.estado_servicio_social,
    e.estado_expediente,
    a.en_sii_08_sep,
    a.en_sii_18_sep,
    CASE
        WHEN e.estado_expediente = 'Inscrito en SII sin Anteproyecto' AND NOT a.en_sii_08_sep AND a.en_sii_18_sep
            THEN 'ALTA TARDÍA EN SII (18 SEP) SIN ENTREGAR HOJAS'
        WHEN e.estado_expediente = 'Inscrito en SII sin Anteproyecto'
            THEN 'INSCRITO EN SII DESDE 08 SEP SIN ENTREGAR HOJAS'
        WHEN e.estado_expediente = 'Pausado / Sin Oficio'
            THEN 'TRÁMITE PAUSADO / INCONCLUSO POR EL ALUMNO'
        WHEN a.estado_servicio_social <> 'Liberado'
            THEN 'ALERTA: SERVICIO SOCIAL NO VERIFICADO / NO LIBERADO'
        ELSE 'CASO ESPECIAL / REASIGNACIÓN'
    END AS tipo_anomalia,
    e.titulo_anteproyecto,
    e.observaciones
FROM expedientes_residencias e
JOIN alumnos a ON e.numero_control = a.numero_control
WHERE e.estado_expediente IN (
        'Inscrito en SII sin Anteproyecto',
        'Pausado / Sin Oficio',
        'Detenido por Servicio Social',
        'Caso Especial / Reasignación'
      )
   OR a.estado_servicio_social <> 'Liberado'
ORDER BY e.estado_expediente, a.nombre_completo;

-- Vista 4: KPIs Ejecutivos para el Panel de Control
CREATE OR REPLACE VIEW v_kpis_dashboard AS
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) FILTER (WHERE e.estado_expediente = 'Expediente Completo') AS expedientes_completos,
    COUNT(*) FILTER (WHERE e.estado_expediente IN ('En Revisión por Academia', 'Pendiente Asignar Asesor (Academia)', 'En Trámite (Falta Oficio Asesor)')) AS pendientes_academia_o_oficio,
    COUNT(*) FILTER (WHERE e.estado_expediente = 'Pausado / Sin Oficio') AS tramites_pausados,
    COUNT(*) FILTER (WHERE a.estado_servicio_social <> 'Liberado') AS alertas_servicio_social,
    COUNT(*) FILTER (WHERE e.estado_expediente = 'Inscrito en SII sin Anteproyecto') AS en_sii_sin_anteproyecto
FROM expedientes_residencias e
JOIN alumnos a ON e.numero_control = a.numero_control;

-- ============================================================================
-- 7. CARGA DE DATOS REALES DESDE LOS 2 ARCHIVOS EXCEL
-- ============================================================================

-- 7.1 Usuarios Administrativos (2 de Gestión y 1 de Academia)
INSERT INTO usuarios_sistema (username, nombre_mostrar, rol, correo, responsabilidad) VALUES
('gestion_1', 'Coordinación de Gestión y Vinculación (Usuario 1)', 'GESTION_1', 'gestion1.industrial@tecnm.mx', 'Recepción de solicitudes impresas, verificación de Servicio Social y emisión de Oficios P.A y P.B'),
('gestion_2', 'Coordinación de Gestión y Vinculación (Usuario 2)', 'GESTION_2', 'gestion2.industrial@tecnm.mx', 'Recepción de solicitudes impresas, seguimiento de correos, archivo y control de casos pausados'),
('academia_ind', 'Academia de Ingeniería Industrial', 'ACADEMIA', 'academia.industrial@tecnm.mx', 'Revisión técnica de anteproyectos y asignación equitativa de Docentes Asesores Internos');


-- 7.2 Plantilla de 42 Docentes (Hoja Maestros de 26-1 ASIGNACION DE ASESORES.xlsx)
INSERT INTO docentes_asesores (id_docente, nombre_docente, jornada, beca, historico_proy_ene_jun, historico_interno_ene_jun, historico_proy_ago_dic, historico_interno_ago_dic) VALUES
(1, 'Alvarez Cruz Enedina', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 3, 0),
(2, 'Barbosa Moreno Alfonso', '40 hrs'::jornada_docente_enum, 'EDD', 3, 2, 2, 0),
(3, 'Castillo Bolaños Blanca Nelva', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 2, 0),
(4, 'Contreras Alvarez Carolina', 'Por horas'::jornada_docente_enum, 'Ninguna', 1, 0, 1, 0),
(5, 'Contreras Mata Margarita', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(6, 'Espinosa Velasco Juan Carlos', '20 hrs'::jornada_docente_enum, 'Ninguna', 1, 0, 2, 0),
(7, 'Escobar Pineda Susana Patricia', 'Por horas'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(8, 'Esquivel Rodriguez Jesus', '30 hrs'::jornada_docente_enum, 'Ninguna', 1, 0, 1, 0),
(9, 'Garcia Alvarado Ma Elena', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 2, 0),
(10, 'Galvez Choy Jorge Alberto', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 2, 0),
(11, 'Galvan Narvaez Jorge Daniel', '40 hrs'::jornada_docente_enum, 'EDD', 3, 1, 1, 0),
(12, 'Giron Flores Francisco Eduardo', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(13, 'Giron Mendoza David', 'Por horas'::jornada_docente_enum, 'Ninguna', 0, 0, 0, 0),
(14, 'Goldaracena Otero Bernardo', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(15, 'Guevara Martinez Fernando', '20 hrs'::jornada_docente_enum, 'Ninguna', 1, 0, 0, 0),
(16, 'Guerrero Rodriguez Ma Cristina', '40 hrs'::jornada_docente_enum, 'EDD', 4, 0, 1, 0),
(17, 'Gutierrez Salas Angela Aurora', 'Por horas'::jornada_docente_enum, 'Ninguna', 1, 0, 1, 0),
(18, 'Gutierrez Treviño Jose Alvaro', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(19, 'Hernandez Mendoza Jose Refugio', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 2, 0),
(20, 'Hernandez Morales Veronica', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 2, 0),
(21, 'Lopez de Lara Gonzalez Ricardo', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 1, 0),
(22, 'Lucio Silva Jose Luis', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 2, 0),
(23, 'Malibran Dominguez Gabriela', 'Por horas'::jornada_docente_enum, 'Ninguna', 0, 0, 1, 0),
(24, 'Mar Orozco Carlos Eusebio', '40 hrs'::jornada_docente_enum, 'EDD', 3, 1, 2, 0),
(25, 'Merinos Herrera Erick Orlando', 'Por horas'::jornada_docente_enum, 'Ninguna', 1, 0, 1, 0),
(26, 'Merinos Orlando', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(27, 'Molar Orozco Juan Flavio', 'Por horas'::jornada_docente_enum, 'Ninguna', 1, 0, 3, 0),
(28, 'Moreno Salazar Ruben', 'Por horas'::jornada_docente_enum, 'Ninguna', 1, 0, 1, 0),
(29, 'Olivares Flores Virginia', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(30, 'Pancardo Perez Jannya', 'Por horas'::jornada_docente_enum, 'Ninguna', 1, 0, 1, 0),
(31, 'Peña Garcia Guillermo Carlos', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 2, 0),
(32, 'Quilantan Garza Victor Manuel', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 1, 0),
(33, 'Quilantan Melian Linda Isabel', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 2, 0),
(34, 'Rivera Toscano Cesar David', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 2, 0),
(35, 'Ronzon Campos Armando', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(36, 'Rodriguez Piton Pedro', '40 hrs'::jornada_docente_enum, 'Ninguna', 1, 0, 2, 0),
(37, 'Silva Cobos Francisco Javier', '30 hrs'::jornada_docente_enum, 'Ninguna', 1, 0, 1, 0),
(38, 'Treviño Valenzuela Roberto Jesús', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 2, 0),
(39, 'Torres Gonzalez Brenda Jassive', 'Por horas'::jornada_docente_enum, 'Ninguna', 1, 0, 1, 0),
(40, 'Vazquez Lara Arturo', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(41, 'Vazquez Ochoa Lorena Margarita', '40 hrs'::jornada_docente_enum, 'Ninguna', 2, 0, 1, 0),
(42, 'Zavala Arce Margarita', '40 hrs'::jornada_docente_enum, 'EDD', 3, 0, 1, 0);
SELECT setval('docentes_asesores_id_docente_seq', (SELECT MAX(id_docente) FROM docentes_asesores));

-- 7.3 Catálogo de Empresas Receptoras extraídas de los expedientes
INSERT INTO empresas_receptoras (id_empresa, nombre_empresa) VALUES
(1, '300+ SPORTS S.A. DE C.V.'),
(2, 'ACABADOS Y RECUBRIMIENTOS DECORATIVOS DE TAMAULIPAS S.A. DE C.V.'),
(3, 'AGENCIA CONSIGNATARIA DEL GOLFO S.A. DE C.V.'),
(4, 'AGUILA FABRICACION'),
(5, 'AGUILA MANTENIMIENTO INDUSTRIAL, S.A. DE C.V.'),
(6, 'AGUILA MANTENIMIENTO INDUSTRIAL,S.A. DE C.V.'),
(7, 'AGUILA MAQUINARIA, MONTAJE Y SERVICIOS ESPECIALIZADOS'),
(8, 'AIREPROYECTOS DEL GOLFO S.A. DE C.V.'),
(9, 'ALIANZA ESTRATEGICA PORTUARIA'),
(10, 'ALMACENES IBARA S.A. DE C.V.'),
(11, 'ALTAMIRA TERMINAL PORTUARIA S.A. DE C.V.'),
(12, 'ANSA INGENIERIA Y CONTROL'),
(13, 'AON COMERCIAL INDUSTRIAL Y DE SERVICIOS DEL NORTE'),
(14, 'ARAC DE LA SULTANA S.A. DE C.V.'),
(15, 'ASTILLERO DE MARINA NO.2'),
(16, 'ASTILLERO DE MARINA NUMERO DOS (ASTIMAR-2) ‘’ALMIRANTE JESUS SANTAMARIA CARRERA’’'),
(17, 'BMW GROUP PLANTA SAN LUIS POTOSI'),
(18, 'BOMAC LATINOAMERICA S.A. DE C.V.'),
(19, 'CALIBRACIONES E INSTRUMENTACION PARA LA INDUSTRIA'),
(20, 'CARSANT DISTRIBUCIONES S. DE R.L. DE C.V.'),
(21, 'CASER PROYECTOS'),
(22, 'CENTRO ESPAÑOL DE TAMPICO A.C.'),
(23, 'CFE CENTRAL TERMOELÉCTRICA DE ALTAMIRA'),
(24, 'CFE DISTRIBUCION'),
(25, 'CFE TRANSMISIÓN TAMPICO'),
(26, 'COMERCIALIZADORA E INTEGRADORA DE PRODUCTOS Y SERVICIOS GEMA,S.A. DE C.V.'),
(27, 'COMISIÓN FEDERAL DE ELECTRICIDAD'),
(28, 'COMPLEJO PROCESADOR DE GAS ARENQUE'),
(29, 'CONCRETOS HUASTECA'),
(30, 'CONSTRUCCIONES E INFRAESTRUCTURA DE TAMAULIPAS S. DE R.L. DE C.V.'),
(31, 'CONSTRUCTORA Y URBANIZADORA DIRA S.A. DE C.V.'),
(32, 'CONSULTORIA EN OBRA S.A. DE C.V.'),
(33, 'CONSULTORIA SIMAL S.A. DE C.V.'),
(34, 'CONSULTORÍA EN OBRA, S.A. DE C.V.'),
(35, 'CONSULTORÍA GISMMA S.A. DE C.V.'),
(36, 'CONTROL DE FLUIDOS INDUSTRIALES S.A. DE C.V.'),
(37, 'DISTRIBUIDORA DE DIESEL RIO PANUCO, S.A. DE C.V.'),
(38, 'DYNASOL'),
(39, 'ENER MANTENIMIENTO INTEGRAL S.A. DE C.V.'),
(40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.'),
(41, 'FAURENCIA SISTEMAS AUTOMOTRICES DE MEXICO'),
(42, 'GASIFICADORA DEL GOLFO S DE R.L. DE C.V.'),
(43, 'GCX INTERMODAL S.A. DE C.V.'),
(44, 'GEMA CAPACITACION Y CONSULTORIA HSEQ'),
(45, 'GEOIL COMPANY'),
(46, 'GRUPO ALIANZA ESTRATEGICA PORTUARIA'),
(47, 'GRUPO BIMBO'),
(48, 'GRUPO CASSIL S.A. DE C.V.'),
(49, 'GRUPO GAREL S.A. DE C.V.'),
(50, 'GRUPO GEREZ'),
(51, 'GRUPO INDUSTRIAL AGUILA S.A. DE C.V.'),
(52, 'GRUPO TAMPICO'),
(53, 'GRUPO ZUDEM S.A. DE C.V.'),
(54, 'HALDEX PRODUCTS DE MEXICO'),
(55, 'INDELPRO'),
(56, 'INDELPRO,S.A. DE C.V.'),
(57, 'INFRAESTRUCTURA PORTUARIA MEXICANA'),
(58, 'INGENIO SAN MIGUEL DEL NARANJO'),
(59, 'INMOBILIARIA MORAN'),
(60, 'INNOVAGAN ,S.A. DE C.V.'),
(61, 'INNOVAGAN S.A.S. DE C.V.'),
(62, 'INSTITUTO NACIONAL ELECTORAL'),
(63, 'INSTITUTO TECNOLOGICO DE CIUDAD MADERO'),
(64, 'INSTRUMENTACION, VALVULAS Y REFACCIONES S.A. DE C.V.'),
(65, 'KSB DE MEXICO S.A. DE C.V.'),
(66, 'LONDON OFFSHORE CONSULTANTS MEXICO S.A. DE C.V.'),
(67, 'MEXICHEM RESINAS VINILICAS S.A. DE C.V.'),
(68, 'MISHUE CONCENTRADORA'),
(69, 'MULTIENLACES LOGÍSTICOS TERRESTRES,S.A. DE C.V.'),
(70, 'NISSAN MADERO'),
(71, 'PAN RICO PAN'),
(72, 'PEMEX GAS Y PETROQUIMICA BASICA CPG ARENQUE'),
(73, 'PEMEX LOGISTICA TASP MADERO'),
(74, 'PETROLEOS MEXICANOS'),
(75, 'QUANTUM ENERGIA'),
(76, 'RADDARE EPCM MEXICO S.A. DE C.V.'),
(77, 'RENTCO CONSTRUCCIÓN & MACHINERY, S.A. DE C.V.'),
(78, 'ROCO DISTRIBUIDORA SOLAR Y WELECTRICA'),
(79, 'SECATMX (SERVICIOS ELECTRONICOS CIENTIFICOS ADMINISTRATIVOS Y TECNICOS)'),
(80, 'SECRETARIA DE MARINA DIRECCIÓN GENERAL DE CONSTRUCCIONES NAVALES'),
(81, 'SECRETARÍA DE MARINA ASTILLERO DE MARINA 2'),
(82, 'SERVICIOS CORPORATIVOS GGA DE GRUPO GAREL'),
(83, 'SERVICIOS PROFESIONALES GGA S.A. DE C.V.'),
(84, 'SERVICIOS TECNICOS PETROLEROS NACIONALES,S.A. DE C.V.'),
(85, 'SIEMENS ENERGY S.A. DE C.V.'),
(86, 'SINDICATO PETROQUÍMICO SECCION 7'),
(87, 'SOCIEDAD NACIONAL PROMOTORA DE BECARIOS S.C.'),
(88, 'SOLUCIONES INTEGRALES MANTENIMIENTO MECANICO Y SOLDADURA, S.A. DE C.V.'),
(89, 'SOS SOLUCIONES SOSTENIBLES'),
(90, 'TEISA S.A. DE C.V.'),
(91, 'TIENDAS CHEDRAUI S.A. DE C.V.'),
(92, 'TIENDAS CHEDRAUI, S.A. DE C.V.'),
(93, 'UNITRANS S.A. DE C.V.'),
(94, 'US FARATHANE S.A. DE S.V.'),
(95, 'VESTOLIT'),
(96, 'VIBRANTS ERACHEM MEXICO,S.A. DE C.V.'),
(97, 'WELDING & COATING LAB (OSCAR PADRÓN DOMÍNGUEZ)');
SELECT setval('empresas_receptoras_id_empresa_seq', (SELECT MAX(id_empresa) FROM empresas_receptoras));

-- 7.4 Padrón de Alumnos (183 números de control únicos de Protocolos y SII)
INSERT INTO alumnos (numero_control, nombre_completo, especialidad, en_sii_08_sep, en_sii_18_sep, estado_servicio_social) VALUES
('19071803', 'MORALES MEDELLÍN ANGEL DE JESÚS', 'Industrial General', FALSE, FALSE, 'Por verificar (Posible falta de S.S.)'::estado_servicio_social_enum),
('21070873', 'ALONSO GARCÍA EDUARDO AQUILEO', 'Industrial General', FALSE, FALSE, 'Por verificar (Posible falta de S.S.)'::estado_servicio_social_enum),
('21071023', 'SANTISBÓN CAMPA ANDREA', 'CALIDAD Y PRODUCTIVIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20070016', 'HERNÁNDEZ CASTRO LESLY SUHEY', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071052', 'VÉLEZ TORRES EDUARDO JOSÉ', 'CALIDAD Y PRODUCTIVIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070099', 'SALAZAR GALVÁN PAOLA ZARETH', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071045', 'LUNA HERRERA JOSÉ MIGUEL', 'Industrial General', FALSE, FALSE, 'Por verificar (Posible falta de S.S.)'::estado_servicio_social_enum),
('21070944', 'MEDINA REZA JAIME VINICIO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('19071953', 'GONZÁLEZ HERNÁNDEZ PEDRO IVÁN', 'CALIDAD Y PRODUCTIVIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070989', 'MARTÍNEZ TOLEDO MANUEL ALEJANDRO', 'Industrial General', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071035', 'BARRAGÁN GLORIA HASSIEL', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('19070499', 'FLORES JUÁREZ JOSÉ LUIS', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070967', 'ACOSTA CASTILLO IBETH ALEXANDER', 'CALIDAD Y PRODUCTIVIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070884', 'LEDEZMA REYES LUIS FERNANDO', 'CALIDAD Y PRODUCTIVIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071117', 'TORRES LARA SIXTO ARMANDO', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071217', 'PERKINS RIVERA RICARDO', 'Industrial General', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071408', 'HERNANDEZ MARTINEZ SANDRA BERENICE', 'Industrial General', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070890', 'ROSALES ROJAS ARIADNA AZENETH', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071090', 'LUCAS RAMIREZ LIZET GUADALUPE', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071127', 'SAAVEDRA DIAZ GRISSELDA', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071101', 'GARCIA GOMEZ VICTOR HUGO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071071', 'LOAIZA SALVADOR KARLA ITZEL', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070964', 'PAVON ORTÍZ JENNIFER JAQUELINE', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('12071121', 'MIGUEL DOMINGO GUSTAVO ANGEL', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071442', 'MARTINEZ SERVIN JESUS EDUARDO', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071022', 'RUIZ REYES LEONARDO', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21690367', 'RODRIGUEZ CRUZ ENRIQUE', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071515', 'MAR VERA JUAN OMAR', 'Industrial General', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071039', 'GARDUÑO MARTINEZ VICENTE RAMON', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071450', 'TURRUBIATES GALLEGOS HECTOR FABIAN', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070102', 'MONTOYA MARTINEZ TRISTAN ANTONIO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071384', 'MARTÍNEZ RODRÍGUEZ YAZMÍN GUADALUPE', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071349', 'HERÁNDEZ CRUZ DAVID EDUARDO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070978', 'VICTORIANO SANTIAGO MARIA GUADALUPE', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070877', 'VAZQUEZ DE LOS SANTOS YOLOTZIN YAMILE', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070914', 'BAUTISTA LUNA VALERIA MICHELL', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071511', 'HIDALGO RAMÍREZ CLAUDIA KARIME', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070915', 'CHAVIRA OLGUIN SIDNEY JANIK', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071027', 'GUZMÁN TORRES XIMENA MONTSERRAT', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('23070002', 'HERRERA CHANEZ BRANDON JESÚS', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('19070358', 'LLANAS LOPEZ ANGEL ALFONSO', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071382', 'MARQUEZ LONGORIA JUAN MIGUEL', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071511', 'GUZMÁN MARTÍNEZ EDUARDO FRANCISCO', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071009', 'RESENDIZ RANGEL IVAN RAFAEL', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071321', 'GUZMÁN LÓPEZ UBALDO', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070088', 'GARCÍA PALOMINO JAQUELINE MONSERRAT', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071468', 'MONTEJO SOBREVILLA ENRIQUE MARIO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071457', 'DEL ANGEL ROMERO BENNY JAIR', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071113', 'ZUÑIGA MONTELONGO ANGEL GAEL', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070958', 'HERNÁNDEZ MARTÍNEZ PAOLA IVON', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071518', 'VILLALTA AVILA JOSE ROMAN', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071041', 'GUZMAN MAR JESUS', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071025', 'CRUZ ESCOBEDO MARIA CRISTINA', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070925', 'GARCIA LOREDO DAVID FILIBERTO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070972', 'RIOS CHONG GUILLERMO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070901', 'ROCHA MACIAS MARTIN ALEJANDRO', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071345', 'GUERRERO LOPEZ ALFREDO', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('16071052', 'SIERRA ZARAZUA OSCAR ISAAC', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070971', 'PULIDO PULIDO ALEJANDRO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071033', 'DEL ANGEL MORALES SEBASTIAN', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071522', 'PEREZ VIZCAYA KARLA ELIZABETH', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071245', 'HERNANDEZ LOREDO TRISTAN NEFTALY', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071137', 'MANCILLA RODRIGUEZ ALEXIS HELAMAN', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('C22071133', 'CURA MEDINA RAUL ALEJANDRO', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20070211', 'RAZA REYES MOHAMMAD ALI', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071019', 'LOPEZ BUENO JUAN MANUEL', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071094', 'MONTOYA CRUZ LUZAIRAM SUSEJEVAY', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071497', 'MERCADO RUIZ CARLOS IVAN', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070950', 'VIDAL CRUZ REBECA JAQUELINE', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070999', 'HARO MARTINEZ OMAR DE JESUS', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070093', 'MARTINEZ CONSTANTINO JESUS ALFONSO', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071422', 'ROJAS DIAZ ANYELL ISAIR', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071049', 'PEREZ CASTILLO TRIANA DALAY', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071230', 'MARTÍNEZ VARGAS JUAN DIEGO', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070831', 'OCHOA HERNANDEZ MARIANA ISABEL', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20070246', 'MEDINA MONTEJO FEDERICO', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('19070339', 'LOPEZ FLORES ANTONIA', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071976', 'URIEGAS LOPEZ JOSE FERNANDO', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071240', 'CARRILLO REYES ANDREA SELENE', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071005', 'MUEDANO MARTINEZ ANDRES', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('19070501', 'CANO GOMEZ YOSIRIS MICHEL', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21070991', 'RANGEL SANCHEZ MANUEL', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071054', 'DEL ANGEL DEL ANGEL MARCO ANTONIO', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071355', 'MAR ALTAMIRANO ESTRELLA MICHELL', 'LOGÍSTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('19070353', 'CAMACHO GUEVARA NICOLAS', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('24070164', 'ANDRADE CASTELLANOS PAOLA', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071519', 'GONZALEZ RAMIREZ XIMENA YULIE', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20070240', 'PEREZ MARTINEZ IRVING MISAEL', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071088', 'ESPARZA MAR ARLETHE', 'LOGÍSTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070075', 'RIOS ESCOBAR NINFA YENITZEL', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071261', 'CASTILLO PADRÓN JONATHAN', 'CALIDAD', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071305', 'SALDAÑA BARRIOS LUISA FERNANDA', 'Industrial General', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071356', 'MEDRANO BULNES JOSE GUADALUPE', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('20071358', 'MEDRANO MARTINEZ CARLOS LEONEL', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070856', 'HERNANDEZ TORRES NADIA JAZMIN', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070879', 'DE LA PAZ CARRANZA VANNYA', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070817', 'FRANCISCO ROCHA ADER', 'MANUFACTURA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21071100', 'CORONADO MARTÍNEZ BRAYAN ISSAC', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070806', 'MORALES PELAEZ ANA PERLA', 'Industrial General', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070737', 'REYES CRUZ JARED ALFREDO', 'Industrial General', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070799', 'ZAVALA VAZQUEZ JUAN ANTONIO', 'MANUFACTURA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070893', 'FAJARDO HERNÁNDEZ ILDERICE', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070842', 'HERBERT MARTINEZ MIGUEL ANGEL', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070873', 'LOREDO GARCIA LUIS AXEL', 'MANUFACTURA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('20071315', 'CUEVAS ORTA HANIA LIZBETH', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22071327', 'SANCHEZ ALVAREZ ARIEL JIMENA', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070839', 'CORTÉS HERNÁNDEZ MÓNICA LIZETH', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21070886', 'MEAVE PONCE DANNA PAOLA', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070726', 'JUAREZ SOTO NAYLA VALENTINA', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070740', 'BANDA BARRAN ROGELIO', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070828', 'GÓMEZ ORTA YSSEL AYLIN', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070807', 'MESEÑO ALVARADO RODRIGO', 'Industrial General', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21071032', 'ALVARADO GARCÍA JOSÉ ERNESTO', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070744', 'PÉREZ RUÍZ JOSÉ LUIS', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070748', 'HERNANDEZ DIEGO', 'MANUFACTURA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21070922', 'ALADRO GONZÁLEZ SARA', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070790', 'GARCÍA CASTRO CARLOS EDUARDO', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070838', 'CARPIO RAMOS HECTOR FABIAN', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21070959', 'JUÁREZ MONTELONGO MARÍA FERNANDA', 'LOGÍSTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21071115', 'GUZMAN ROMAN ANGEL RICARDO', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21071515', 'CASTRO RODRIGUEZ NEMESIS MICHELLE', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('21071109', 'ALANIS GALLEGOS YAHIR AGUSTIN', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21071106', 'MARIN MARTÍNEZ KAREN YULIANA', 'MANUFACTURA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070749', 'ORTIZ JIMENEZ LUIS ALBERTO', 'MANUFACTURA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22071201', 'AGUILAR LÓPEZ MARÍA FERNANDA', 'MANUFACTURA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070741', 'CRUZ PEREZ JOSE VICENTE', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070822', 'RODRIGUEZ RUIZ RODRIGO DE JESUS', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070791', 'GUERRERO MARTINEZ OSCAR ALEJANDRO', 'Industrial General', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070947', 'SILVA CRUZ LUCIANO', 'LOGÍSTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('20071416', 'ROJAS RODRIGUEZ PERLA ESMERALDA', 'LOGISTICA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070747', 'GARCÍA FERNANDEZ DANIELA', 'CALIDAD Y PRODUCTIVIDAD', FALSE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21071517', 'RAMIREZ WALLE KAREN JUDITH', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21071081', 'LACIO HERNÁNDEZ ANTONIO ALEXANDER', 'MANUFACTURA', FALSE, FALSE, 'Liberado'::estado_servicio_social_enum),
('22070902', 'LUGO YAÑEZ LESLY PAOLA', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22071342', 'SOLIS GALVAN DANIELA IDALY', 'CALIDAD', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070781', 'LOZANO HERNÁNDEZ SAMANTHA', 'Industrial General', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070867', 'FLORS SILVA ISAAC ROBERTO', 'Industrial General', FALSE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070843', 'MARTINEZ RODRIGUEZ ANGEL TADEO', 'Industrial General', FALSE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070885', 'CRUZ VIDAL TANIA', 'Industrial General', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21070864', 'VARGAS TORRES DULCE KARINA', 'Industrial General', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070758', 'HERNANDEZ REYES KEYLA GUADALUPE', 'Industrial General', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22071325', 'GÓMEZ MACÍAS DORA ANGÉLICA', 'LOGISTICA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('22070803', 'LOGINOS LÓPEZ MARVIC ARODI', 'MANUFACTURA', TRUE, TRUE, 'Liberado'::estado_servicio_social_enum),
('21071139', 'AMBROCIO HERNANDEZ MARCO ANTONIO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071503', 'ANDRADE MERAZ DELIA JOHANA', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070867', 'ARGUELLES HERNANDEZ ALMIR DE JESUS', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070725', 'AYALA MARTINEZ LUIS ENRIQUE', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070753', 'BAEZA LARIOS SHARIS ZAYARI', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071636', 'BAPTISTE AYALA GEORGE', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070923', 'BARRON RIVERA YOZGART YAHIR', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070884', 'CRUZ GARCIA MIGUEL ANGEL', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22071193', 'DE CASTRO BALDERAS GRACE ALEJANDRA', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071635', 'DE LA LIMA HERNANDEZ BLANCA ESTHER', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070852', 'ESPINOSA MELENDEZ MARIA FERNANDA', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070800', 'GARCIA UVARIO OLIVER EDUARDO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070904', 'GASPAR RAMIREZ ZURISADAI', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071146', 'GONZALEZ HERNANDEZ MARIA DEL ROSARIO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070956', 'GUERRERO VALDOVINOS JOSSELYN', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071000', 'HERNANDEZ CHAVEZ LUIS EDUARDO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070917', 'HERNANDEZ GOMEZ CARLOS MIGUEL', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071028', 'HERNANDEZ VICENTE ANGEL IVAN', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070907', 'JUAREZ MARTINEZ ZABDIEL', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070858', 'LOPEZ HERNANDEZ DIANA LAURA', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071029', 'MARCOS DEL ANGEL ISAID', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('20071299', 'MARTINEZ HERNANDEZ LEONARDO JOEL', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('C20070520', 'MONTALVO RODRIGUEZ IRVING ELISEO', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070924', 'OCHOA RUIZ CRISTIAN MATEO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070743', 'OROZCO LOPEZ JORGE EDUARDO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070938', 'PECERO ZEFERINO JOSE EDUARDO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070929', 'PEREZ CANCHE DIEGO OSVALDO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070775', 'RAMIREZ ROJAS ALFONSO YAHIR', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071523', 'RAMOS MORA NANCY CAROLINA', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('19070566', 'RANGEL DEL TORO JUAN ANDRES', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070947', 'RODRIGUEZ GONZALEZ DANNA SOFIA', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('20071423', 'RODRIGUEZ RAMOS BRAYAN EDUARDO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071075', 'ROJAS GUZMAN ALEXIS RAFAEL', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21071084', 'ROJAS LALE LUVYN ANGEL', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('20071278', 'ROSAS NAVA ROCIO BELEN', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('20071280', 'RUIZ DIAZ ABRAHAM GERARDO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070875', 'SANCHEZ DIAZ DERIAN RAFAEL', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('21070934', 'SERRANO CELESTINO JULIA NATALI', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('22070863', 'VALLES GUZMAN CRISTIAN EDUARDO', 'Por definir', TRUE, TRUE, 'Por verificar'::estado_servicio_social_enum),
('23070118', 'VARGAS SANTIAGO BRENDA MICHEL', 'Por definir', FALSE, TRUE, 'Por verificar'::estado_servicio_social_enum);

-- 7.5 Expedientes de Residencias (144 protocolos entregados + 40 inscritos en SII sin hojas)
INSERT INTO expedientes_residencias (
    id_expediente, numero_control, semestre, titulo_anteproyecto, id_empresa, nombre_empresa_texto,
    asesor_externo, horario_asistencia, periodo_realizacion, fecha_entrega_fisica, nota_entrega_fisica,
    fecha_entrega_academia, oficio_autorizacion, fecha_impresion_oficio_aut, fecha_notificado_alumno,
    fecha_envio_aut_correo, revisado_academia, id_docente_asesor, nombre_asesor_interno_texto,
    folio_control_academia, oficio_asignacion_asesor, fecha_envio_asesor_correo,
    estado_expediente, observaciones
) VALUES
(1, '19071803', 'Ago-Dic 2026', 'DESARROLLO DE MANUAL TECNICO DE HVAC EN EMPRESA AIRE PROYECTOS DEL GOLFO', 8, 'AIREPROYECTOS DEL GOLFO S.A. DE C.V.', NULL, NULL, NULL, '2026-02-02'::DATE, NULL, '2026-02-06'::DATE, NULL, NULL, NULL, NULL, 'Si'::dictamen_academia_enum, 42, 'Margarita Zavala Arce', '26-1-1', NULL, NULL, 'Pausado / Sin Oficio'::estado_expediente_enum, 'Dejó trámite pausado tras revisión de academia'),
(2, '21070873', 'Ago-Dic 2025', 'ELABORACION DE UNA SIMULACION A ESCALA DE LA PUESTA A FLOTE DEL PROYECTO DE CONSTRUCCION LA COMPUERTA DE DIQUE SECO DEL (CENREPMAD-1)', 15, 'ASTILLERO DE MARINA No.2', NULL, NULL, NULL, '2026-02-06'::DATE, NULL, '2026-02-06'::DATE, NULL, NULL, NULL, NULL, 'Si'::dictamen_academia_enum, 12, 'Francisco Eduardo Giron Flores', '26-1-1', NULL, NULL, 'Pausado / Sin Oficio'::estado_expediente_enum, 'Dejó trámite pausado tras revisión de academia'),
(3, '21071023', 'Ene-Jun 2026', 'OPTIMIZACION DEL PROCESO DE CONTROL DE GESTION EN EL AREA MARINA DE ABL', 66, 'LONDON OFFSHORE CONSULTANTS MEXICO S.A. DE C.V.', 'ING. ALLAN NAREZO REYNA', 'DE 09:00 A 15:00 HORAS', '11 FEBRERO 2026 AL 13 JUNIO 2026', '2026-02-20'::DATE, NULL, '2026-02-23'::DATE, 'P.A013/2026', '2026-03-13'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 1, 'M.A. ENEDINA ALVAREZ CRUZ', '26-1-1', 'P.B023/2026', '2026-03-26'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(4, '20070016', 'Ene-Jun 2026', 'IDENTIFICACION Y MITIGACION DE RIESGOS OPERATIVOS EN MANIOBRAS DE IZAJE OFFSHORE', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'LIC. PATRICIA SANDOVAL CRESPO', 'DE 08:00 A 18:00 HORAS', '19 ENERO 2026 AL 19 MAYO 2026', '2026-02-20'::DATE, NULL, '2026-02-23'::DATE, 'P.A011/2026', '2026-03-13'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 29, 'ING. VIRGINIA OLIVARES FLORES', '26-1-1', 'P.B021/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(5, '21071052', 'Ago-Dic 2025', 'DISEÑO DE UN SISTEMA ESTANDARIZADO PARA LA ADMINISTRACION Y CONTROL DE EQUIPOS DE MEDICION, GAGES Y FIXTURES EN EL AREA DE METROLOGIA DE LA EMPRESA US FARATHANE PLANTA APODACA', 94, 'US FARATHANE S.A. DE S.V.', 'ING. JESUS CONTRERAS ROSALES', 'DE 07:30 A 16:30 HORAS', '04 NOVIEMBRE 2025 AL 04 MAYO 2026', '2026-02-20'::DATE, NULL, '2026-02-23'::DATE, 'P.A010/2026', '2026-03-06'::DATE, NULL, '2026-03-06'::DATE, 'Si'::dictamen_academia_enum, 38, 'ING. ROBERTO TREVIÑO VALENZUELA', '26-1-1', 'P.B020/2026', '2026-03-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(6, '21070099', 'Ago-Dic 2025', 'DISEÑO DE UN MODELO DE OPTIMIZACION DE LOS PROCESOS OPERATIVOS EN EL AREA DE REPARACIONES NAVALES', 81, 'SECRETARÍA DE MARINA ASTILLERO DE MARINA 2', '1ER. MTRE. SIA. JOSE MARTIN MENDOZA LOREDO', 'DE 07:00 A 16:00 HORAS', '22 SEPTIEMBRE 2025 AL 22 ENERO 2026', '2026-02-20'::DATE, NULL, '2026-02-23'::DATE, 'P.A012/2026', '2026-03-09'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 16, 'M.C. MA. CRISTINA GUERRERO RODRIGUEZ', '26-1-1', 'P.B022/2026', '2026-03-24'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(7, '21071045', 'Ago-Dic 2025', 'IMPLEMENTACION DE UN SISTEMA DE CLASIFICACION ABC PARA EL CONTROL Y GESTION DE MATERIALES EN EL AREA DE SERVICIOS GENERALES', 22, 'CENTRO ESPAÑOL DE TAMPICO A.C.', NULL, NULL, NULL, '2026-02-25'::DATE, NULL, '2026-02-25'::DATE, NULL, NULL, NULL, NULL, 'Si'::dictamen_academia_enum, 24, 'Carlos Eusebio Mar Orozco', '26-1-1', NULL, NULL, 'Pausado / Sin Oficio'::estado_expediente_enum, 'Dejó trámite pausado tras revisión de academia'),
(8, '21070944', 'Ene-Jun 2026', 'DISEÑO DE UN SISTEMA DE GESTION INTEGRAL DE CAPACITACION PARA LA
CERTIFICACION DEL PERSONAL QUE REALIZA ACTIVIDADES DE ALTO RIESGO EN CFE TAMPICO', 27, 'COMISIÓN FEDERAL DE ELECTRICIDAD', 'ING. VICTOR ARTURO PACHECO CRUZ', 'DE 09:00 A 15:00 HORAS', '03 FEBRERO 2026 AL 05 JUNIO 2026', '2026-02-25'::DATE, NULL, '2026-02-25'::DATE, 'P.A015/2026', '2026-03-13'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 33, 'ING. LINDA ISABEL QUILANTÁN MELIAN', '26-1-1', 'P.B024/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(9, '19071953', 'Ago-Dic 2025', 'DISEÑO E IMPLEMENTACION DE PROGRAMA DE MANTENIMIENTO PREVENTIVO PARA BANDAS TRANSPORTADORAS', 13, 'AON COMERCIAL INDUSTRIAL Y DE SERVICIOS DEL NORTE', 'ING. VICENTE ENRIQUE MAR BARRIOS', 'DE 07:00 A 17:00 HORAS', '17 AGOSTO 2025 AL 17 DICIEMBRE 2025', '2026-02-25'::DATE, NULL, '2026-02-25'::DATE, 'P.A017/2026', '2026-03-05'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 25, 'ING. ORLANDO MERINOS', '26-1-1', 'P.B026/2026', '2026-03-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(10, '21070989', 'Ago-Dic 2025', 'ELABORACION DE UNA SIMULACION A ESCALA DE LA PUESTA A FLOTE DEL PROYECTO DE CONSTRUCCION LA COMPUERTA DE DIQUE SECO DEL (CENREPMAD-1)', 16, 'ASTILLERO DE MARINA NUMERO DOS (ASTIMAR-2) ‘’ALMIRANTE JESUS SANTAMARIA CARRERA’’', 'TENIENTE CORBETA GUILLERMO RODRÍGUEZ JUÁREZ', 'DE 07:00 A 15:00 HORAS', '28 OCTUBRE 2025 AL 10 FEBRERO 2026', '2026-02-26'::DATE, NULL, '2026-02-26'::DATE, 'P.A018/2026', '2026-03-02'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 30, 'M.A.I JANNYA PANCARDO PEREZ', '26-1-1', 'P.B027/2026', '2026-03-10'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(11, '21071035', 'Ene-Jun 2026', 'DISEÑO Y DESARROLLO DE UNA PLATAFORMA MODULAR PARA LA GRABADORA LASER DE LA EMPRESA INNOVAGAN S.A.S. DE C.V.', 61, 'INNOVAGAN S.A.S. DE C.V.', 'ING. ANTONIO ABAD RAMIREZ RODRIGUEZ', 'DE 09:00 A 17:00 HORAS', '15 ENERO 2026 AL 15 JULIO 2026', '2026-03-03'::DATE, NULL, '2026-03-03'::DATE, 'P.A019/2026', '2026-03-06'::DATE, '2026-09-11'::DATE, NULL, 'Si'::dictamen_academia_enum, 34, 'M.I.A. CÉSAR DAVID RIVERA TOSCANO', '26-1-1', 'P.B029/2026', '2026-09-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(12, '19070499', 'Ago-Dic 2025', 'OPTIMIZACION DEL PROCESO DE CONTROL PRESUPUESTAL EN CFE DISTRIBUCIÓN', 27, 'COMISIÓN FEDERAL DE ELECTRICIDAD', 'LIC. JAIME HUMBERTO ORDAZ DÍAZ', 'DE 10:00 A 16:00 HORAS', '28 NOVIEMBRE 2025 AL 24 ABRIL 2026', '2026-03-04'::DATE, NULL, '2026-03-05'::DATE, 'P.A020/2026', '2026-03-19'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 2, 'DR.ALFONSO BARBOSA MORENO', '26-1-1', 'P.B030/2026', '2026-03-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(13, '21070967', 'Ago-Dic 2025', 'ESTANDARIZACION Y MEJORA DE LA CAPTURA DE LAS CARGAS DE COMBUSTIBLE DE LOS CLIENTES EN EL SISTEMA INTERNO DE FACTURACION PARA INCREMENTAR LA EFICIENCIA OPERATIVA', 49, 'GRUPO GAREL S.A. DE C.V.', 'LIC. ISKRA ZORAIDA PAEZTANGUMA', 'DE 09:30 A 13:30 HORAS', '01 SEPTIEMBRE 2025 AL 01 MARZO 2026', '2026-03-09'::DATE, NULL, '2026-03-12'::DATE, 'P.A021/2026', '2026-05-12'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 19, 'Jose Refuguio Hernandez Mendoza', '26-1-1', 'P.B031/2026', '2026-05-19'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(14, '21070884', 'Ago-Dic 2025', 'OPTIMIZACION DEL PROCESO DE FACTURACION DE LOS TICKETS DE CONSUMOS DE CARGA DE CLIENTES', 49, 'GRUPO GAREL S.A. DE C.V.', 'LIC. ISKRA ZORAIDA PAEZ TANGUMA', 'DE 09:30 A 13:30 HORAS', '01 SEPTIEMBRE 2026 AL 01 MARZO 2026', '2026-03-09'::DATE, NULL, '2026-03-12'::DATE, 'P.A022/2026', '2026-05-19'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 9, 'Ma Elena García Alvarado', '26-1-1', 'P.B032/2026', '2026-05-21'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(15, '21071117', 'Ago-Dic 2025', 'DISEÑO E IMPLEMENTACION DE UN MODELO DE REESTRUCTURACION DE 
RUTAS PARA LA MEJORA DEL NIVEL DE SERVICIO EN ALMACENES IBARRA', 10, 'ALMACENES IBARA S.A. DE C.V.', 'LIC. JOSE LUIS GONZALEZ MELO', 'DE 08:00 A 16:00 HORAS', '16 FEBRERO 2026 AL 16 AGOSTO 2026', '2026-03-09'::DATE, NULL, '2026-03-12'::DATE, 'P.A023/2026', '2026-03-19'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 31, 'ING. GUILLERMO CARLOS PEÑA GARCÍA', '26-1-1', 'P.B033/2026', '2026-03-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(16, '20071217', 'Sin especificar', 'MEJORA DEL FLUJO LOGISTICO COMERCIAL DE TICKETS DE FACTURACION MEDIANTE HERRAMIENTAS DE I.I', 49, 'GRUPO GAREL S.A. DE C.V.', 'LIC. ISKRA ZORAIDA PAEZ TANGUMA', 'DE 09:00 A 15:00 HORAS', '09 FEBRERO 2026 AL 18 JUNIO 2026', '2026-03-10'::DATE, NULL, '2026-03-12'::DATE, 'P.A024/2026', NULL, NULL, NULL, 'Pendiente'::dictamen_academia_enum, 22, 'José Luis Lucio Silva', '26-1-1', 'P.B034/2026', NULL, 'Pendiente Asignar Asesor (Academia)'::estado_expediente_enum, NULL),
(17, '20071408', 'Ago-Dic 2025', 'OPTIMIZACION DEL PROCESO DE RECLUTAMIENTO Y SELECCION MEDIANTE LA CREACION DE UN BANCO DE TALENTO APLICANDO HERRAMIENTAS DE INGENIERIA INDUSTRIAL EN EL AREA DE RECURSOS HUMANOS', 93, 'UNITRANS S.A. DE C.V.', 'ING. MARIA FERNANDA HERNANDEZ ROCHA', 'DE 08:30 A 18:15 HORAS', '06 OCTUBRE 2025 AL 06 MARZO 2026', '2026-03-10'::DATE, NULL, '2026-03-12'::DATE, 'P.A025/2026', '2026-03-23'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 5, 'DRA. MARGARITA CONTRERAS MATA', '26-1-1', 'P.B035/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(18, '21070890', 'Ene-Jun 2026', 'Actualización y mejora del plan de respuesta a emergencias del CPG Arenque', 28, 'COMPLEJO PROCESADOR DE GAS ARENQUE', 'ING. CARLOS LEOBARDO GONZALEZ SANCHEZ', 'DE 08:00 14:00 HORAS', '23 FEBRERO 2026 AL 24 JUNIO 2026', '2026-03-10'::DATE, NULL, '2026-03-12'::DATE, 'P.A026/2026', '2026-03-19'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 11, 'ING. JORGE DANIEL GALVAN NARVAEZ', '26-1-1', 'P.B036/2026', '2026-03-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(19, '21071090', 'Ene-Jun 2026', 'OPTIMIZACION DE LOS PROCEDIMIENTOS DE EVALUACION, MANTENIMIENTO Y VERIFICACION FUNCIONAL DE VALVULAS DE RELEVO DE PRESION PARA FORTALECER LA GESTION DE LA INTEGRIDAD OPERATIVA EN DUCTOS Y RECIPIENTES A PRESION DEL CPG ARENQUE', 28, 'COMPLEJO PROCESADOR DE GAS ARENQUE', 'ING. CARLOS LEOBARDO GONZALEZ SANCHEZ', 'DE 08:00 14:00 HORAS', '23 FEBRERO 2026 AL 24 JUNIO 2026', '2026-03-10'::DATE, NULL, '2026-03-12'::DATE, 'P.A027/2026', '2026-03-19'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 14, 'ING. BERNARDO GOLDARACENA OTERO', '26-1-1', 'P.B037/2026', '2026-03-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(20, '21071127', 'Ene-Jun 2026', 'ANALISIS Y MEJORA DEL PROCESO DE CONTROL Y GESTION DE CAPACITACIONES PARA OPTIMIZAR LA EMISION DE CONSTANCIAS DC3 EN LA EMPRESA ESEASA OFFSHORE', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'LIC. PATRICIA SANDOVAL CRESPO', 'DE 08:00 A 18:00 HORAS', '16 ENERO 2026 AL 16 MAYO 2026', '2026-03-12'::DATE, NULL, '2026-03-13'::DATE, 'P.A028/2026', '2026-03-20'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 3, 'M.C. BLANCA NELVA CASTILLO BOLAÑOS', '26-1-1', 'P.B038/2026', '2026-03-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(21, '21071101', 'Ene-Jun 2026', 'OPTIMIZACION DE LOS SERVICIOS INTERNOS DE TRANSPORTE Y COMEDOR MEDIANTE EL DISEÑO E IMPLEMENTACIÓN DE MEJORAS EN ESEASA OFFSHORE S.A. DE C.V.', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'LIC. PATRICIA SANDOVAL CRESPO', 'DE 08:00 A 18:00 HORAS', '19 ENERO 2026 AL 19 MAYO 2026', '2026-03-12'::DATE, NULL, '2026-03-13'::DATE, 'P.A029/2026', '2026-03-19'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 40, 'DR. ARTURO VAZQUEZ LARA', '26-1-1', 'P.B039/2026', '2026-03-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(22, '21071071', 'Ago-Dic 2025', 'DESARROLLO DE UNA BASE DE DATOS PARA OPTIMIZAR EL SISTEMA DE CONTROL Y REGISTRO DEL PRODUCTO TERMINADO EN EL AREA DE CALIDAD', 72, 'PEMEX GAS Y PETROQUIMICA BASICA CPG ARENQUE', 'LIC. DUNIA ISELA ARGUELLO CONDE', 'DE 08:00 A 14:00 HORAS', '14 OCTUBRE 2025 AL 11 FEBRERO 2026', '2026-03-12'::DATE, NULL, '2026-03-13'::DATE, 'P.A030/2026', '2026-03-19'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 36, 'ING. PEDRO RODRÍGUEZ PITON', '26-1-1', 'P.B040/2026', '2026-03-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(23, '21070964', 'Ene-Jun 2026', 'ANALISIS Y OPTIMIZACION DEL PROCESO DE PROCURA EN ESEASA OFFSHORE MEDIANTE INDICADORES DE RENDIMIENTO', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. RUBEN OJEDA ARGUELLO', 'DE 08:00 A 18:00 HORAS', '21 ENERO 2026 AL 21 MAYO 2026', '2026-03-18'::DATE, NULL, '2026-03-19'::DATE, 'P.A031/2026', '2026-03-25'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 18, 'ING. JOSE ALVARO GUTIERREZ TREVIÑO', '26-1-1', 'P.B041/2026', '2026-03-26'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(24, '12071121', 'Ene-Jun 2026', 'OPTIMIZACION DEL PROCESO DE SOLICITUD, SURTIDO Y REGISTRO DE MATERIALES EN EL ALMACEN GENERAL DE ESEASA', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. JAVIER ALEJANDRO SAUCEDO VALDEZ', 'DE 08:00 A 18:00 HORAS', '24 FEBRERO 2026 AL 24 JULIO 2026', '2026-03-18'::DATE, NULL, '2026-03-19'::DATE, 'P.A032/2026', '2026-03-23'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 32, 'ING. VICTOR MANUEL QUILANTAN GARZA', NULL, 'P.B042/2026', '2026-03-25'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(25, '20071442', 'Ene-Jun 2026', 'OPTIMIZACION DEL PROCESO DE CONTROL, MANEJO Y RESGUARDO DE LOS DOCUMENTOS EN EL AREA DE INGENIERIA', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. RICARDO RODRIGUEZ CADENA', 'DE 08:00 A 18:00 HORAS', '05 FEBRERO 2026 AL 05 JUNIO 2026', '2026-03-18'::DATE, NULL, '2026-03-19'::DATE, 'P.A033/2026', '2026-05-07'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 20, 'VERONICA HERNANDEZ MORALES', '26-1-1', 'P.B043/2026', '2026-05-12'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(26, '21071022', 'Ago-Dic 2025', 'REDISEÑO DEL PROCESO DE RECEPCION DE UNIDADES AUTOMOTRICES EN ATP MEDIANTE LA AUTOMATIZACION DEL REGISTRO EN EL CENTRO REGULADOR', 11, 'ALTAMIRA TERMINAL PORTUARIA S.A. DE C.V.', 'LIC. NOHEMI GONZALEZ AVALOS', 'DE 07:00 A 13:00 HORAS', '09 FEBRERO 2026 AL 09 JUNIO 2026', '2026-03-20'::DATE, NULL, '2026-03-20'::DATE, 'P.A034/2026', '2026-03-24'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 41, 'M.C. LORENA MARGARITA VAZQUEZ OCHOA', '26-1-1', 'P.B044/2026', '2026-03-26'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(27, '21690367', 'Ene-Jun 2026', 'ACTUALIZACION DE DIAGRAMAS DE TUBERIA E INSTRUMENTACION DE LA PLANTA COMBINADA BA, DE ACUERDO CON EL ELEMENTO DE ADMINISTRACIONES AL CAMBIO', 74, 'PETROLEOS MEXICANOS', 'ING. OMAR SAID GONZALEZ', 'DE 08:00 A 14:00 HORAS', '23 FEBRERO 2026 AL 23 JUNIO 2026', '2026-03-20'::DATE, NULL, '2026-03-20'::DATE, 'P.A035/2026', '2026-03-24'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 21, 'M.C. RICARDO LOPEZ DE LARA GONZALEZ', NULL, 'P.B045/2026', '2026-03-26'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(28, '20071515', 'Ene-Jun 2025', 'APLICACION DE LA NOM-006-STPS-2017 PARA MEJORAR LAS CONDICIONES DE SEGURIDAD Y SALUD EN EL ALMACENAMIENTO DE MATERIALES EN BOMAC LATINOAMERICA S.A. DE C.V.', 18, 'BOMAC LATINOAMERICA S.A. DE C.V.', 'ING. EDGAR SANTIAGO GUZMAN', 'DE 08:00 A 16:00 HORAS', '28 ABRIL 2026 AL 29 AGOSTO 2026', NULL, 'REASIGNACIÓN', NULL, 'P.A093/2025', '2026-03-23'::DATE, NULL, NULL, 'NO'::dictamen_academia_enum, 29, 'ING. VIRGINIA OLIVARES FLORES', '26-1-2', 'P.B001/2025', '2026-03-26'::DATE, 'Caso Especial / Reasignación'::estado_expediente_enum, 'Reasignación de proyecto/asesor'),
(29, '21071039', 'Ago-Dic 2025', 'OPTIMIZACION DEL PROCESO DE PURIFICACION DE AGUA POR OSMOSIS INVERSA MEDIANTE LA EVALUACION, CONTROL Y ESTANDARIZACION DE VARIABLES OPERATIVAS EN SECATMX', 79, 'SECATMX (SERVICIOS ELECTRONICOS CIENTIFICOS ADMINISTRATIVOS Y TECNICOS)', 'ING. JUAN RODRIGUEZ AZUARA', 'DE 08:00 A 16:00 HORAS', '12 NOVIEMBRE 2025 AL 27 MARZO 2026', '2026-03-24'::DATE, NULL, '2026-03-24'::DATE, 'P.A036/2026', '2026-05-05'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 2, 'ALFONSO BARBOSA', '26-1-2', 'P.B046/2026', '2026-05-29'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(30, '20071450', 'Ene-Jun 2026', 'EVALUACION DE LA EFECTIVIDAD DE LOS PROGRAMAS DE CAPACITACION TECNICA Y DE SEGURIDAD INDUSTRIAL EN ESEASA OFFSHORE', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. ARTURO ESEQUIEL SAAVEDRA', 'DE 08:00 A 18:00 HORAS', '28 ENERO 2026 AL 28 MAYO 2026', '2026-03-24'::DATE, NULL, '2026-03-24'::DATE, 'P.A037/2026', '2026-05-05'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 10, 'JORGE ALBERTO GALVEZ CHOY', '26-1-1', 'P.B047/2026', '2026-05-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(31, '21070102', 'Ene-Jun 2026', 'IMPLEMENTACION DEL SISTEMA GLOBALMENTE ARMONIZADO (SGA) EN EL ALMACENAMIENTO SEGURO DE SUSTANCIAS QUIMICAS PELIGROSAS CONFORME A LA NOM-018-STPS-2015', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. EDWIN MICHELL VAZQUEZ TORRES', 'DE 08:00 A 18:00 HORAS', '12 FEBRERO 2026 AL 12 JUNIO 2026', '2026-03-24'::DATE, NULL, '2026-03-24'::DATE, 'P.A138/2026', '2026-05-05'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 35, 'ARMANDO RONZON CAMPOS', '26-1-1', 'P.B048/2026', '2026-05-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(32, '20071384', 'Ene-Jun 2026', 'ANALISIS Y OPTIMIZACION DEL CONTROL DEL MANTENIMIENTO AL PARQUE VEHICULAR DE LA ZONA DE TRANSMISION TAMPICO', 27, 'COMISIÓN FEDERAL DE ELECTRICIDAD', 'LAE. CARLOS AUGUSTO HERRERA MARTINEZ', 'DE 08:00 A 15:30 HORAS', '16 FEBRERO 2026 AL 17 JUNIO 2026', '2026-03-25'::DATE, NULL, '2026-03-25'::DATE, 'P.A039/2026', '2026-05-14'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 37, 'DR. FRANCISCO JAVIER SILVA COBOS', '26-1-1', 'P.B049/2026', '2026-05-20'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(33, '20071349', 'Ene-Jun 2026', 'IMPLEMENTACION DE UN PLAN DE MANTENIMIENTO A LA FLOTILLA VEHICULAR DE RADDARE EPCM MEXICO SA DE CV', 76, 'RADDARE EPCM MEXICO S.A. DE C.V.', 'ING. PAULO MARES PEREZ', 'DE 09:00 A 17:00 HORAS', '10 FEBRERO 2026 AL 15 JUNIO 2026', '2026-03-26'::DATE, NULL, '2026-03-26'::DATE, 'P.A040/2026', '2026-05-05'::DATE, NULL, NULL, 'Si'::dictamen_academia_enum, 8, 'JESÚS ESQUIVEL RODRÍGUEZ', '26-1-2', 'P.B050/2026', '2026-05-25'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(34, '21070978', 'Ene-Jun 2026', 'DISEÑO E IMPLEMENTACION DE UN MANUAL OPERATIVO EN EL AREA DE CONTROL DE ACCESO DE LA EMPRESA ESEASA OFFSHORE S.A. DE C.V.', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'LIC. PATRICIA SANDOVAL CRESPO', 'DE 08:00 A 18:00 HORAS', '09 FEBRERO 2026 AL 09 JUNIO 2026', '2026-03-26'::DATE, NULL, '2026-03-26'::DATE, 'P.A041/2026', '2026-05-06'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 1, 'ENEDINA ALVAREZ CRUZ', '26-1-2', 'P.B051/2026', '2026-05-19'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(35, '21070877', 'Ene-Jun 2026', 'IMPLEMENTACION DE UNA PLATAFORMA PARA LA GESTION Y ACTUALIZACION DE EXPEDIENTES DE PERSONAL EN EL AREA DE RECURSOS HUMANOS', 25, 'CFE TRANSMISIÓN TAMPICO', 'LAE. CARLOS AUGUSTO HERRERA MARTINEZ', 'DE 08:00 A 15:30 HORAS', '19 FEBRERO 2026 AL 26 JUNIO 2026', '2026-03-26'::DATE, NULL, '2026-03-26'::DATE, 'P.A042/2026', '2026-05-06'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 20, 'VERONICA HERNANDEZ MORALES', '26-1-2', 'P.B052/2026', '2026-05-25'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(36, '21070914', 'Ene-Jun 2026', 'OPTIMIZACION DE RUTAS PARA EL TRANSPORTE DE CARGA SOBREDIMENSIONADA EN PESADO TRANSPORT', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. CARLOS NEFI MARTÍNEZ AMAYA', 'DE 08:00 A 18:00 HORAS', '18 MARZO 2026 AL 18 JULIO 2026', '2026-04-14'::DATE, NULL, '2026-04-14'::DATE, 'P.A043/2026', '2026-05-07'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 24, 'CARLOS EUSEBIO MAR OROZCO', '26-1-2', 'P.B053/2026', '2026-05-12'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(37, '21071511', 'Ene-Jun 2026', 'DISEÑO E IMPLEMENTACION DE UN SISTEMA DE EVALUACION DEL RENDIMIENTO DE LOS TALLERES MEDIANTE KPIs EN EL DEPARTAMENTO DE REPARACIONES', 16, 'ASTILLERO DE MARINA NUMERO DOS (ASTIMAR-2) ‘’ALMIRANTE JESUS SANTAMARIA CARRERA’’', 'TENIENTE CORBETA SIA. I.M. ALFREDO ADRIÁN VELÁZQUEZ CASADOS', 'DE 07:00 A 13:00 HORAS', '10 MARZO 2026 AL 09 JULIO 2026', '2026-04-15'::DATE, NULL, '2026-04-15'::DATE, 'P.A044/2026', '2026-05-06'::DATE, '2026-09-14'::DATE, NULL, 'SI'::dictamen_academia_enum, 34, 'CÉSAR DAVID RIVERA TOSCANO', '26-1-2', 'P.B054/2026', '2026-09-14'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(38, '21070915', 'Ago-Dic 2025', 'PROPUESTA DE MEJORA DEL PROCESO DE RECEPCIÓN Y REGISTRO DE SOLICITUDES MEDIANTE UN SISTEMA DE CONTROL EN EXCEL', 86, 'SINDICATO PETROQUÍMICO SECCION 7', 'ENRIQUE HERRERA HERNÁNDEZ', 'DE 09:00 A 18:00 HORAS', '27 AGOSTO 2025 AL 27 DICIEMBRE 2025', '2026-04-16'::DATE, NULL, '2026-04-17'::DATE, 'P.A045/2026', '2026-05-08'::DATE, '2026-06-02'::DATE, NULL, 'SI'::dictamen_academia_enum, 11, 'ING. JORGE DANIEL GALVAN NARVAEZ', '26-1-2', 'P.B055/2026', '2026-06-03'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(39, '21071027', 'Ago-Dic 2025', 'OPTIMIZACION EN LA ADMINISTRACION Y EL CONTROL DE LOS INVENTARIOS EN CONSIGNACION DE LA EMPRESA CARSANT', 20, 'CARSANT DISTRIBUCIONES S. DE R.L. DE C.V.', 'LIC. ANA LAURA ADAME CARRERA', 'DE 09:00 A 17:30 HORAS', '19 NOVIEMBRE 2025 AL 19 MAYO 2026', '2026-04-20'::DATE, NULL, '2026-04-20'::DATE, 'P.A046/2026', '2026-05-06'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 16, 'MA. CRISTINA GUERRERO RODRÍGUEZ', '26-1-2', 'P.B056/2026', '2026-06-03'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(40, '23070002', 'Ene-Jun 2026', 'DESARROLLO DE UN SISTEMA DE GESTIÓN DE SEGURIDAD INDUSTRIAL EN OPERACIONES DE DRAGADO EN ESEASA OFFSHORE', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. JOHN HEBER GUERRERO CRUZ', 'DE 08:00 A 18:00 HORAS', '10 MARZO 2026 AL 08 JULIO 2026', '2026-04-22'::DATE, NULL, '2026-04-22'::DATE, 'P.A047/2026', '2026-05-06'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 9, 'MA. ELENA GARCÍA ALVARADO', '26-1-2', 'P.B057/2026', '2026-05-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(41, '19070358', 'Ene-Jun 2026', 'APLICACION DE LA METODOLOGIA SMED PARA OPTIMIZAR CAMBIOS DE MODELO Y TIEMPOS DE CICLO EN CELDAS DE SOLDADURA', 41, 'FAURENCIA SISTEMAS AUTOMOTRICES DE MEXICO', 'ING. SAUL GUSTAVO RAMOS ZUÑIGA', 'DE 08:00 A 16:00 HORAS', '08 ENERO 2026 AL 08 JULIO 2026', '2026-04-21'::DATE, NULL, '2026-05-25'::DATE, 'P.A048/2026', '2026-05-28'::DATE, '2026-06-02'::DATE, '2026-06-02'::DATE, 'SI'::dictamen_academia_enum, 21, 'RICARDO LOPEZ DE LARA GONZALEZ', '26-1-2', 'P.B058/2026', '2026-06-02'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(42, '20071382', 'Ene-Jun 2026', 'DESARROLLO E IMPLEMENTACION DE UN SISTEMA DIGITAL COMPARTIDO QUE PERMITA EL CONTROL, REGISTRO Y SEGUIMIENTO DE LA FACTURACION EN LA EMPRESAA ESEASA', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. IRIS ANATEYAK GARCIA CORTEZ', 'DE 08:00 A 18:00 HORAS', '09 MARZO 2026 AL 09 JULIO 2026', '2026-04-21'::DATE, NULL, '2026-04-27'::DATE, 'P.A049/2026', '2026-05-25'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 34, 'CESAR DAVID RIVERA TOSCANO', '26-1-3', 'P.B059/2026', '2026-06-01'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(43, '20071511', 'Ene-Jun 2026', 'DIAGNOSTICO INTEGRAL DE SEGURIDAD, ILUMINACION Y CUMPLIMIENTO NORMATIVO EN UNA ESTACION DE SERVICIO', 82, 'SERVICIOS CORPORATIVOS GGA DE GRUPO GAREL', 'ING. VIRIDIANA MORA ROSAS', 'DE 09:00 A 18:00 HORAS', '19 ENERO 2026 AL 19 MAYO 2026', '2026-04-30'::DATE, NULL, '2026-05-08'::DATE, 'P.A050/2026', '2026-05-25'::DATE, '2026-05-28'::DATE, NULL, 'SI'::dictamen_academia_enum, 2, 'ALFONSO BARBOSA MORENO', '26-1-3', 'P.B060/2026', '2026-05-27'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(44, '21071009', 'Ene-Jun 2026', 'ANALISIS DE TIEMPOS EN EL PROCESO DE CAPTURA DE INFORMACION DE LOS TRACTOCAMIONES EN EL AREA DE PUERTA ATP', 11, 'ALTAMIRA TERMINAL PORTUARIA S.A. DE C.V.', 'LIC. BENITA GUADALUPE VALLES GARZA', 'DE 09:00 A 15:00 HORAS', '29 ENERO 2026 AL 29 JULIO 2026', '2026-05-12'::DATE, NULL, '2026-05-20'::DATE, 'P.A051/2026', '2026-05-25'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 9, 'Ma Elena García Alvarado', '26-1-3', 'P.B061/2026', '2026-05-27'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(45, '20071321', 'Ene-Jun 2026', 'IMPLEMENTACION DE UN SISTEMA DE CONTROL DE COSTOS POR PROYECTO CON EL FIN DE MEJORAR LA GESTION FINANCIERA EN EL DEPARTAMENTO DE CONTABILIDAD', 2, 'ACABADOS Y RECUBRIMIENTOS DECORATIVOS DE TAMAULIPAS S.A. DE C.V.', 'LIC. GEMA YUDITH ARMENTA CALLES', 'DE 08:00 A 18:00 HORAS', '02 MARZO 2026 AL 02 JULIO 2026', '2026-05-18'::DATE, NULL, '2026-05-19'::DATE, 'P.A052/2026', '2026-05-21'::DATE, '2026-05-22'::DATE, NULL, 'SI'::dictamen_academia_enum, 1, 'ENEDINA ALVAREZ CRUZ', '26-1-3', 'P.B062/2026', '2026-05-22'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(46, '21070088', 'Ene-Jun 2026', 'ELABORACION DE UN ESTUDIO DE FACTIBILIDAD PARA LA AUTOMATIZACIÓN DEL CONTROL DE ACCESO DE CONTENEDORES MEDIANTE TECNOLOGIA OCR', 11, 'ALTAMIRA TERMINAL PORTUARIA S.A. DE C.V.', 'ING. CYNTIA ALEJANDRA SANCHEZ VEGA', 'DE 09:00 A 15:00 HORAS', '30 ENERO 2026 AL 30 JULIO 2026', '2026-05-18'::DATE, NULL, '2026-05-19'::DATE, 'P.A053/2026', '2026-05-21'::DATE, '2026-05-22'::DATE, NULL, 'SI'::dictamen_academia_enum, 7, 'SUSANA PATRICIA ESCOBAR PINEDA', '26-1-1', 'P.B063/2026', '2026-05-22'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(47, '20071468', 'Ene-Jun 2026', 'OPTIMIZACION DE LOS PROCESOS DE ENTRADA, RESGUARDO Y SALIDA DE MATERIALES EN EL ALMACEN GENERAL DE ESEASA OFFSHORE', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. HECTOR SANTOS WESTPHAL', 'DE 08:00 A 18:00 HORAS', '19 FEBRERO 2026 AL 19 JULIO 2026', '2026-05-19'::DATE, NULL, '2026-05-20'::DATE, 'P.A054/2026', '2026-05-25'::DATE, '2026-05-28'::DATE, NULL, 'SI'::dictamen_academia_enum, 32, 'VICTOR MANUEL QUILANTAN GARZA', '26-1-2', 'P.B064/2026', '2026-05-28'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(48, '20071457', 'Ene-Jun 2026', 'ELABORACION DE UNA GUIA PARA EL PROCESO DE CERTIFICACION BAJO LA NORMA ISO 39001', 45, 'GEOIL COMPANY', 'ING. FERNANDO MAURICIO ACOSTA GONE', 'DE 10:00 A 16:00 HORAS', '10 MARZO 2026 AL 10 JULIO 2026', '2026-05-19'::DATE, NULL, '2026-05-20'::DATE, 'P.A055/2026', '2026-05-25'::DATE, '2026-05-28'::DATE, '2026-06-02'::DATE, 'SI'::dictamen_academia_enum, 42, 'MARGARITA ZAVALA ARCE', '26-1-2', 'P.B065/2026', '2026-05-28'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(49, '21071113', 'Ene-Jun 2026', 'DESARROLLO DE LA PROPUESTA DE UN SISTEMA DE GESTIÓN DE SEGURIDAD VIAL BAJO LA NORMA ISO 39001', 45, 'GEOIL COMPANY', 'ING. FERNANDO MAURICIO ACOSTA GONE', 'DE 10:00 A 16:00 HORAS', '10 MARZO 2026 AL 10 JULIO 2026', '2026-05-19'::DATE, NULL, '2026-05-20'::DATE, 'P.A056/2026', '2026-05-25'::DATE, '2026-05-28'::DATE, NULL, 'SI'::dictamen_academia_enum, 17, 'ANGELA AURORA GUTIÉRREZ SALAS', '26-1-1', 'P.B066/2026', '2026-05-28'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(50, '21070958', 'Ene-Jun 2026', 'ACTUALIZACION Y HOMOLOGACION DE LOS DESCRIPTIVOS DE PUESTOS DEL MINI NEGOCIO DE LABORATORIO DE FABRICA EN EL INGENIO SAN MIGUEL DEL NARANJO', 58, 'INGENIO SAN MIGUEL DEL NARANJO', 'ING. ANA PANO RODRIGUEZ', 'DE 09:00 A 14:00 HORAS', '04 MAYO 2026 AL 04 SEPTIEMBRE 2026', '2026-05-20'::DATE, NULL, '2026-05-20'::DATE, 'P.A057/2026', '2026-05-25'::DATE, '2026-05-28'::DATE, NULL, 'SI'::dictamen_academia_enum, 24, 'CARLOS EUSEBIO MAR OROZCO', '26-1-3', 'P.B067/2026', '2026-05-28'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(51, '21071518', 'Ene-Jun 2026', 'OPTIMIZACION DEL PROCEDIMIENTO DE INGRESO,OPERACION Y SALIDA DE LAS UNIDADES DE CARGA EN LOS PATIOS DE LA TERMINAL IPM', 57, 'INFRAESTRUCTURA PORTUARIA MEXICANA', 'ING. SERVANDO LIÑAN CALZADA', 'DE 08:00 A 16:00 HORAS', '26 MARZO 2026 AL 31 JULIO 2026', '2026-05-13'::DATE, NULL, '2026-05-20'::DATE, 'P.A058/2026', '2026-05-25'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 3, 'BLANCA NELVA CASTILLO', '26-1-3', 'P.B068/2026', '2026-05-27'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(52, '21071041', 'Ene-Jun 2026', 'IMPLEMENTACION DE KPIs PARA LA OPTIMIZACION EN EL AREA DE CONTROL DE ACCESO EN ESEASA OFFSHORE S.A. DE C.V.', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'LIC. PATRICIA SANDOVAL CRESPO', 'DE 08:00 A 18:00 HORAS', '30 MARZO 2026 AL 28 JULIO 2026', '2026-05-20'::DATE, NULL, '2026-05-27'::DATE, 'P.A059/2026', '2025-05-28'::DATE, '2026-06-02'::DATE, NULL, 'SI'::dictamen_academia_enum, 33, 'LINDA ISABEL QUILANTAN MELIAN', '26-1-2', 'P.B069/2026', '2026-06-02'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(53, '21071025', 'Ene-Jun 2026', 'DISEÑO DE UN MANUAL DE PROCEDIMIENTOS ENFOCADO EN LA ACTIVIDAD DE ESTIMACIONES PARA EL AREA DE FACTURACION', 7, 'AGUILA MAQUINARIA, MONTAJE Y SERVICIOS ESPECIALIZADOS', 'ING. ANA IVONNE HERNANDEZ FLORES', 'DE 08:00 A 18:00 HORAS', '17 MARZO 2026 AL 17 SEPTIEMBRE 2026', '2026-05-27'::DATE, NULL, '2026-05-28'::DATE, 'P.A060/2026', '2026-06-03'::DATE, '2026-06-03'::DATE, NULL, 'SI'::dictamen_academia_enum, 33, 'LINDA ISABEL QUILANTAN MELIAN', '26-1-3', 'P.B070/2026', '2026-06-03'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(54, '21070925', 'Ene-Jun 2026', 'APLICACION DEL CICLO PHVA EN EL CONTROL DE DOCUMENTOS DEL AREA DE TESORERIA Y PRESUPUESTOS DE CFE CON BASE A LOS LINEAMIENTOS DE LA NORMA ISO 9001', 27, 'COMISIÓN FEDERAL DE ELECTRICIDAD', 'LIC. JAIME HUMBERTO ORDAZ DÍAZ', 'DE 10:00 A 16:00 HORAS', '04 MAYO 2026 AL 04 SEPTIEMBRE 2026', '2026-05-27'::DATE, NULL, '2026-05-28'::DATE, 'P.A061/2026', '2026-06-03'::DATE, '2026-06-03'::DATE, NULL, 'SI'::dictamen_academia_enum, 20, 'VERONICA HERNANDEZ MORALES', '26-1-3', 'P.B071/2026', '2026-06-03'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(55, '21070972', 'Ene-Jun 2026', 'DISEÑO DE UN PLAN DE SOSTENIBILIDAD PARA LA EMPRESA COFISA', 36, 'CONTROL DE FLUIDOS INDUSTRIALES S.A. DE C.V.', 'ING. SOFIA MARISOL VEGA HERNANDEZ', 'DE 08:00 A 16:00 HORAS', '14 MAYO 2026 AL 14 SEPTIEMBRE 2026', '2026-05-27'::DATE, NULL, '2026-05-28'::DATE, 'P.A062/2026', '2026-06-03'::DATE, '2026-06-03'::DATE, NULL, 'SI'::dictamen_academia_enum, 42, 'MARGARITA ZAVALA ARCE', '26-1-3', 'P.B072/2026', '2026-08-27'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(56, '21070901', 'Ene-Jun 2026', 'OPTIMIZACION DEL FLUJO DE INFORMACION OPERATIVA PARA LA REDUCCION DEL LEAD TIME EN LA CADENA DE SUMINISTRO INTERNA DE GCX', 43, 'GCX INTERMODAL S.A. DE C.V.', 'C.P. ASCENSION HUMBERTO MARTINEZ CASTILLO', 'DE 09:00 A 13:00 HORAS', '23 MARZO 2026 AL 23 SEPTIEMBRE 2026', '2026-05-28'::DATE, NULL, '2026-05-28'::DATE, 'P.A063/2026', '2026-06-03'::DATE, '2026-06-03'::DATE, NULL, 'SI'::dictamen_academia_enum, 16, 'MA. CRISTINA GUERRERO RODRÍGUEZ', '26-1-3', 'P.B073/2026', '2026-06-03'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(57, '20071345', 'Ene-Jun 2026', 'DESARROLLO DE UN MANUAL DE OPERACION PARA LOS SISTEMAS AUTOMATICOS CONTRA INCENDIO TIPO DILUVIO MEDIANTE EL ANALISIS, DOCUMENTACION Y ESTANDARIZACION DE PROCEDIMIENTOS OPERATIVOS', 75, 'QUANTUM ENERGIA', 'ING. NESTOR HUGO RIVAS HERNANDEZ', 'DE 08:00 A 16:00 HORAS', '30 MARZO 2026 AL 30 JULIO 2026', '2026-05-28'::DATE, NULL, '2026-05-28'::DATE, 'P.A064/2026', '2026-06-03'::DATE, '2026-06-03'::DATE, NULL, 'SI'::dictamen_academia_enum, 31, 'CARLOS GUILLERMO PEÑA GARCIA', '26-1-2', 'P.B074/2026', '2026-06-03'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(58, '16071052', 'Ene-Jun 2026', 'ELABORACION DE PROGRAMA INTERNO DE PROTECCION CIVIL DEL CENTRO DE TRABAJO SIMAL CORPORATIVO', 33, 'CONSULTORIA SIMAL S.A. DE C.V.', 'ING. JORGE ARTURO MAYA CHI', 'DE 08:00 A 18:00 HORAS', '05 DICIEMBRE 2025 AL 05 ABRIL 2026', '2026-05-29'::DATE, NULL, '2026-06-01'::DATE, 'P.A065/2026', '2026-06-03'::DATE, '2026-06-03'::DATE, NULL, 'SI'::dictamen_academia_enum, 11, 'JORGE DANIEL GALVAN NARVAEZ', '26-1-3', 'P.B075/2026', '2026-06-03'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(59, '21070971', 'Ene-Jun 2026', 'DESARROLLO DE UN SISTEMA DE CONTROL OPERATIVO DE MANTENIMIENTO A LOS EQUIPOS DE LA EMPRESA SOLUCIONES INTEGRALES', 88, 'SOLUCIONES INTEGRALES MANTENIMIENTO MECANICO Y SOLDADURA, S.A. DE C.V.', 'ING. ISMAEL LENTO PAREDES', 'DE 08:00 A 17:00 HORAS', '18 MAYO 2026 AL 18 SEPTIEMBRE 2026', '2026-06-01'::DATE, NULL, '2026-06-01'::DATE, 'P.A066/2026', '2026-06-03'::DATE, '2026-06-03'::DATE, NULL, 'SI'::dictamen_academia_enum, 32, 'VICTOR MANUEL QUILANTAN GARZA', '26-1-3', 'P.B076/2026', '2026-06-03'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(60, '21071033', 'Ene-Jun 2026', 'OPTIMIZACION DE LOS PROCESOS ADMINISTRATIVOS MEDIANTE UN SISTEMA DE CONTROL Y SEGUIMIENTO DE ACTIVIDADES', 49, 'GRUPO GAREL S.A. DE C.V.', 'LIC. ISKRA ZORAIDA PAEZ TANGUMA', 'DE 09:00 A 14:00 HORAS', '20 MARZO 2026 AL 10 AGOSTO 2026', '2026-06-01'::DATE, NULL, '2026-06-10'::DATE, 'P.A067/2026', '2026-06-23'::DATE, '2026-06-24'::DATE, '2026-06-24'::DATE, 'SI'::dictamen_academia_enum, 22, 'JOSE LUIS LUCIO SILVA', '26-1-2', 'P.B077/2026', '2026-06-24'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(61, '21071522', 'Ene-Jun 2026', 'DISEÑO DE UN SISTEMA DE INDICADORES DE PRODUCTIVIDAD PARA LA EVALUACION OPERATIVA DE UNA FLOTA DE CONCRETO', 29, 'CONCRETOS HUASTECA', 'LIC. TERESA DE JESUS ALANIS LOPEZ', 'DE 09:00 A 14:00 HORAS', '17 MARZO 2026 AL 11 SEPTIEMBRE 2026', '2026-05-26'::DATE, NULL, '2026-06-02'::DATE, 'P.A068/2026', '2026-06-05'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 4, 'CAROLINA CONTRERAS ALVAREZ', '26-1-1', 'P.B078/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(62, '20071245', 'Ene-Jun 2026', 'DISEÑO Y CONSTRUCCION SISTEMA INTELIGENTE PARA EL CONTROL Y MONITOREO DE CONTAMINACION ACUSTICA AMBIENTAL EN ZONAS URBANAS', 63, 'INSTITUTO TECNOLOGICO DE CIUDAD MADERO', 'M.I.A CESAR DAVID RIVERA TOSCANO', 'DE 08:00 A 14:00 HORAS', '01 MARZO 2025 AL 29 JUNIO 2025', '2026-05-29'::DATE, NULL, '2026-06-02'::DATE, 'P.A069/2026', '2026-06-09'::DATE, '2026-06-10'::DATE, NULL, 'SI'::dictamen_academia_enum, 24, 'CARLOS EUSEBIO MAR OROZCO', '26-1-4', 'P.B079/2026', '2026-06-10'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(63, '21071137', 'Ene-Jun 2026', 'DESARROLLO DE UN PROGRAMA DE CAPACITACION PARA PERSONAL DE NUEVO INGRESO EN IVARESA', 64, 'INSTRUMENTACION, VALVULAS Y REFACCIONES S.A. DE C.V.', 'ING. ZAIDA GISELA TARREGA SALDIVAR', 'DE 08:00 A 16:00 HORAS', '06 ABRIL 2026 AL 06 AGOSTO 2026', '2026-06-02'::DATE, NULL, '2026-06-04'::DATE, 'P.A070/2026', '2026-06-05'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 5, 'MARGARITA CONTRERAS MATA', NULL, 'P.B080/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(64, 'C22071133', 'Ene-Jun 2026', 'IMPLEMENTACION DE LA METODOLOGIA 5S PARA LA MEJORA OPERATIVA DEL ALMACEN DE PXG MONTERREY', 1, '300+ SPORTS S.A. DE C.V.', 'LIC. GERARDO VAZQUEZ FLORES', 'DE 10:00 A 17:00 HORAS', '29 ABRIL 2026 AL 29 AGOSTO 2026', '2026-06-02'::DATE, NULL, '2026-06-03'::DATE, 'P.A071/2026', '2026-06-08'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 27, 'JUAN FLAVIO MOLAR OROZCO', '26-1-1', 'P.B081/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(65, '20070211', 'Ene-Jun 2026', 'DISEÑO E IMPLEMENTACION DE UN PLAN DE MANTENIMIENTO PREDICTIVO BASADO EN EL ANALISIS DEL RENDIMIENTO Y LAS PERDIDAS ENERGETICAS EN SISTEMAS FOTOVOLTAICOS', 78, 'ROCO DISTRIBUIDORA SOLAR Y WELECTRICA', 'LIC. CIS COLMENERO ESPINOSA', 'DE 09:00 A 17:00 HORAS', '23 FEBRERO 2026 AL 30 JUNIO 2026', '2026-06-02'::DATE, NULL, '2026-06-02'::DATE, 'P.A072/2026', '2026-06-08'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 6, 'JUAN CARLOS ESPINOZA VELASCO', '26-1-1', 'P.B082/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(66, '21071019', 'Ene-Jun 2026', 'MANUAL INTEGRAL DE PROCESOS Y GESTION DE LA DOCUMENTACION EN LA DISTRIBUIDORA DE DIESEL RIO PANUCO (DDRP)', 37, 'DISTRIBUIDORA DE DIESEL RIO PANUCO, S.A. DE C.V.', 'ING. ALBA NELLY AGUILLON CRUZ', 'DE 09:00 A 18:00 HORAS', '06 MAYO 2026 AL 04 SEPTIEMBRE 2026', '2026-06-03'::DATE, NULL, '2026-06-03'::DATE, 'P.A073/2026', '2026-06-08'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 10, 'JORGE ALBERTO GALVEZ CHOY', '26-1-2', 'P.B083/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(67, '21071094', 'Ene-Jun 2026', 'ACTUALIZACION E IMPLEMENTACION DE UN PLAN DE CONTINGENCIA Y SEGURIDAD INDUSTRIAL EN LA EMPRESA CEITAM', 30, 'CONSTRUCCIONES E INFRAESTRUCTURA DE TAMAULIPAS S. DE R.L. DE C.V.', 'ING. GERARDO ENRIQUEZ ALVARADO', 'DE 08:00 A 14:00 HORAS', '20 ABRIL 2026 AL 28 AGOSTO 2026', '2026-06-03'::DATE, NULL, '2026-06-03'::DATE, 'P.A074/2026', '2026-06-08'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 21, 'RICARDO LOPEZ DE LARA GONZALEZ', '26-1-3', 'P.B084/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(68, '20071497', 'Ene-Jun 2026', 'ANALISIS DE MODO Y EFECTO DE FALLA PARA LA EVALUACION DE UN SISTEMA DE CAPTACION DE AGUA PLUVIAL', 63, 'INSTITUTO TECNOLOGICO DE CIUDAD MADERO', 'M.I.A. CESAR DAVID RIVERA TOSCANO', 'DE 08:00 A 14:00 HORAS', '01 ABRIL 2026 AL 01 AGOSTO 2026', '2026-06-03'::DATE, NULL, '2026-06-03'::DATE, 'P.A075/2026', '2026-06-11'::DATE, '2026-06-15'::DATE, '2026-06-15'::DATE, 'SI'::dictamen_academia_enum, 11, 'JORGE DANIEL GALVAN NARVAEZ', '26-1-4', 'P.B085/2026', '2026-06-15'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(69, '21070950', 'Ene-Jun 2026', 'ANALISIS DE LAS DISCONTINUIDADES EN UNIONES SOLDADAS OFFSHORE MEDIANTE PRUEBAS NO DESTRUCTIVAS Y SU IMPACTO EN LA INTEGRIDAD MECANICA SUBSEA', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ING. EDDI REYES DEL ANGEL', 'DE 08:00 A 18:00 HORAS', '24 MARZO 2026 AL 22 JULIO 2026', '2026-06-03'::DATE, NULL, '2026-06-03'::DATE, 'P.A076/2026', '2026-06-08'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 8, 'JESUS ESQUIVEL RODRIGUEZ', '26-1-1', 'P.B086/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(70, '21070999', 'Ene-Jun 2026', 'IMPLEMENTACION DE UN SISTEMA DE CONTROL, TRAZABILIDAD E IDENTIFICACION DE RECURSOS EN ALMACEN', 64, 'INSTRUMENTACION, VALVULAS Y REFACCIONES S.A. DE C.V.', 'ING. EDITH REYES PEREZ', 'DE 08:00 A 16:00 HORAS', '13 ABRIL 2026 AL 13 AGOSTO 2026', '2026-06-04'::DATE, NULL, '2026-06-04'::DATE, 'P.A077/2026', '2026-06-08'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 15, 'FERNANDO GUEVARA MARTINEZ', '26-1-1', 'P.B087/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(71, '21070093', 'Ene-Jun 2026', 'ESTANDARIZACION Y REDUCCION DE TIEMPOS DE CICLO DE ENSAMBLE', 65, 'KSB DE MEXICO S.A. DE C.V.', 'ING. JESUS GALVAN MORENO', 'DE 08:00 A 14:00 HORAS', '03 FEBRERO 2026 AL 03 JUNIO 2026', '2026-06-04'::DATE, NULL, '2026-06-04'::DATE, 'P.A078/2026', '2026-06-08'::DATE, '2026-06-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 25, 'ERICK ORLANDO MERINOS', '26-1-1', 'P.B088/2026', '2026-06-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(72, '20071422', 'Ene-Jun 2026', 'IMPLEMENTACION DE UN PROGRAMA DE MANTENIMIENTO PREVENTIVO EN GRUPO ZUDEM', 53, 'GRUPO ZUDEM S.A. DE C.V.', 'ING. ABIRAM PEREZ BADILLO', 'DE 08:00 A 13:00 HORAS', '16 ABRIL 2026 AL 05 SEPTIEMBRE 2026', '2026-06-08'::DATE, NULL, '2026-06-08'::DATE, 'P.A079/2026', '2026-06-11'::DATE, '2026-06-15'::DATE, '2026-06-15'::DATE, 'SI'::dictamen_academia_enum, 12, 'FRANCISCO EDUARDO GIRON FLORES', '26-1-2', 'P.B089/2026', '2026-06-15'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(73, '21071049', 'Ene-Jun 2026', 'IMPLEMENTACION DEL SISTEMA DE INTEGRIDAD MECANICA (SIMCU) PARA LA OPTIMIZACIÓN DE INSPECCIONES BASADAS EN RIESGO EN EQUIPOS ESTATICOS Y TUBERIAS.', 67, 'MEXICHEM RESINAS VINILICAS S.A. DE C.V.', 'ING. LUIS URIEL ROCHA DEL ANGEL', 'DE 08:00 A 16:00 HORAS', '30 MARZO 2026 AL 01 SEPTIEMBRE 2026', '2026-06-08'::DATE, NULL, '2026-06-08'::DATE, 'P.A080/2026', '2026-06-11'::DATE, '2026-06-15'::DATE, '2026-06-15'::DATE, 'SI'::dictamen_academia_enum, 14, 'BERNARDO GOLDARACENA OTERO', '26-1-2', 'P.B090/2026', '2026-06-15'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(74, '20071230', 'Ene-Jun 2026', 'IMPLEMENTACION DE UN SISTEMA DE SEGURIDAD EN OBRAS DE INGENIERIA CIVIL BASADO EN NORMAS OFICIALES MEXICANAS (NOM), CON HERRAMIENTAS DE VERIFICACION Y SEGUIMIENTO OPERATIVO', 85, 'SIEMENS ENERGY S.A. DE C.V.', 'ING. MACHUCA MORY DAVID LEONARDO', 'DE 08:00 A 17:00 HORAS', '16 MARZO 2026 AL 20 JULIO 2026', '2026-06-11'::DATE, NULL, '2026-06-11'::DATE, 'P.A081/2026', '2026-06-23'::DATE, '2026-06-24'::DATE, '2026-06-24'::DATE, 'SI'::dictamen_academia_enum, 18, 'JOSE ALVARO GUTIERREZ TREVIÑO', '26-1-2', 'P.B091/2026', '2026-06-24'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(75, '22070831', 'Ene-Jun 2026', 'DISEÑO Y CONSTRUCCION DE UN SISTEMA DE RECUPERACION DE CONDENSADOS UN SISTEMA CAPTADOR DE VAPOR DE AGUA PARA LA DISMINUCION DE GASTO ENERGETICO EN PROCESOS INDUSTRIALES', 63, 'INSTITUTO TECNOLOGICO DE CIUDAD MADERO', 'M.I.A. CESAR DAVID RIVERA TOSCANO', 'DE 09:00 A 14:00 HORAS', '01 ABRIL 2026 AL 01 AGOSTO 2026', '2026-06-10'::DATE, NULL, '2026-06-10'::DATE, 'P.A082/2026', '2026-06-11'::DATE, '2026-06-26'::DATE, '2026-06-26'::DATE, 'SI'::dictamen_academia_enum, 2, 'ALFONSO BARBOSA MORENO', '26-1-4', 'P.B092/2026', '2026-06-26'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(76, '20070246', 'Ene-Jun 2026', 'IMPLEMENTACION DE UN SISTEMA ERP PARA EL CONTROL Y MANEJO DE ENTRADAS Y SALIDAS DE MATERIALES EN EL AREA DE ALMACEN QUE PERMITA OPTIMIZAR LOS INGRESOS Y EGRESOS DE GRUPO CASSIL S.A. DE C.V.', 48, 'GRUPO CASSIL S.A. DE C.V.', 'ING. ANDRES ANTONIO RODRIGUEZ SALAZAR', 'DE 08:00 A 16:00 HORAS', '16 MARZO 2026 AL 17 JULIO 2026', '2026-06-25'::DATE, NULL, '2026-06-25'::DATE, 'P.A083/2026', '2026-06-30'::DATE, NULL, '2026-06-30'::DATE, 'SI'::dictamen_academia_enum, 7, 'SUSANA PATRICIA ESCOBAR PINEDA', '26-1-2', 'P.B093/2026', '2026-06-30'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(77, '19070339', 'Ene-Jun 2026', 'DISEÑO DE UN SISTEMA PARA EL CONTROL DE NOMINA EN UNA EMPRESA PARA LA REDUCCION DE TIEMPOS BASANDOSE EN LA METODOLOGIA SMED', 63, 'INSTITUTO TECNOLOGICO DE CIUDAD MADERO', 'M.I.A. CESAR DAVID RIVERA TOSCANO', 'DE 08:00 A 14:00 HORAS', '01 ABRIL 2026 AL 01 AGOSTO 2026', '2026-06-24'::DATE, NULL, '2026-06-25'::DATE, 'P.A084/2026', '2026-08-04'::DATE, '2026-09-02'::DATE, NULL, 'SI'::dictamen_academia_enum, 2, 'ALFONSO BARBOSA MORENO', '26-1-5', 'P.B094/2026', '2026-09-02'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(78, '20071976', 'Ene-Jun 2026', 'ELABORACION DE UN PROCEDIMIENTO PARA LA APLICACIÓN E INTERPRETACION DE LA PRUEBA NO DESTRUCTIVA POR LIQUIDOS PENETRANTES EN UNIONES SOLDADAS', 90, 'TEISA S.A. DE C.V.', 'LIC. ILSE IBARRA FLORES', 'DE 08:00 A 17:00 HORAS', '30 MARZO 2026 AL 30 AGOSTO 2026', '2026-06-24'::DATE, NULL, '2026-06-25'::DATE, 'P.A085/2026', '2026-06-30'::DATE, '2026-08-13'::DATE, NULL, 'SI'::dictamen_academia_enum, 40, 'ARTURO VAZQUEZ LARA', '26-1-2', 'P.B095/2026', '2026-08-13'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(79, '20071240', 'Ene-Jun 2026', 'EVALUACION DE UN MODELO DE FRANQUICIA PARA LA ESTANDARIZACION Y EXPANSION DE LA PANADERIA PAN RICO PAN', 71, 'PAN RICO PAN', 'YINETH CASTAÑO LIBREROS', 'DE 06:00 A 15:00 HORAS', '20 FEBRERO 2026 AL 20 JUNIO 2026', '2026-06-24'::DATE, NULL, '2026-06-25'::DATE, 'P.A086/2026', '2026-06-30'::DATE, NULL, NULL, 'SI'::dictamen_academia_enum, 35, 'ARMANDO RONZON CAMPOS', '26-1-2', 'P.B096/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(80, '21071005', 'Ene-Jun 2026', 'IMPLEMENTACION DE UN PLAN DE MANTENIMIENTO PREVENTIVO QUE ASEGURE LA CONFIABILIDAD DE LAS SUBESTACIONES ELECTRICAS DE LA EMPRESA ESEASA OFFSHORE', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'ARQ. MARCELA ZAMORA ROJAS', 'DE 08:00 A 18:00 HORAS', '20 MAYO 2026 AL 20 SEPTIEMBRE 2026', '2026-06-26'::DATE, NULL, '2026-06-26'::DATE, 'P.A087/2026', '2026-06-30'::DATE, '2026-08-13'::DATE, NULL, 'SI'::dictamen_academia_enum, 38, 'ROBERTO TREVIÑO VALENZUELA', '26-1-2', 'P.B097/2026', '2026-08-13'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(81, '19070501', 'Ene-Jun 2026', 'DISEÑO DE UN MANUAL DE PROCEDIMIENTOS ESTANDARIZADOS Y CONTROL DE OBRA BAJO LA METODOLOGIA LEAN CONSTRUCTION EN CONSTRUCTORA Y URBANIZADORA DIRA S.A. DE C.V.', 31, 'CONSTRUCTORA Y URBANIZADORA DIRA S.A. DE C.V.', 'ING. JORGE LUIS DIAZ JASSO', 'DE 08:00 A 18:00 HORAS', '09 MARZO 2026 AL10 JULIO 2026', '2026-06-30'::DATE, NULL, '2026-06-30'::DATE, 'P.A088/2026', '2026-10-15'::DATE, '2026-10-16'::DATE, NULL, 'SI'::dictamen_academia_enum, 28, 'RUBEN MORENO SALAZAR', '26-1-1', 'P.B098/2026', '2026-10-16'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(82, '21070991', 'Ene-Jun 2026', 'PROPUESTA DE MEJORA PARA EL SISTEMA CONTRAINCENDIOS DEL DIQUE SECO DEL CENTRO DE REPARACIONES NAVALES', 80, 'SECRETARIA DE MARINA DIRECCIÓN GENERAL DE CONSTRUCCIONES NAVALES', 'TTE. NAV. JOSÉ EMMANUEL ARANO GUZMÁN', 'DE 08:00 A 14:00 HORAS', '22 JUNIO 2026 AL 23 OCTUBRE 2026', '2026-08-05'::DATE, NULL, '2026-08-05'::DATE, 'P.A089/2026', '2026-08-06'::DATE, '2026-08-13'::DATE, NULL, 'SI'::dictamen_academia_enum, 16, 'MA. CRISTINA GUERRERO RODRIGUEZ', '26-1-4', 'P.B099/2026', '2026-08-13'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(83, '21071054', 'Ene-Jun 2026', 'IDENTIFICACION DE LAS CAUSAS , CONDICIONES Y FACTORES DE RIESGO ASOCIADOS A LOS INCIDENTES CON CONSECUENCIA E INCIDENTES POTENCIALES OCURRIDOS EN EL AREA DE PRODUCCION DEL CPG ARENQUE', 28, 'COMPLEJO PROCESADOR DE GAS ARENQUE', 'ING. CARLOS LEOBARDO GONZALEZ SANCHEZ', 'DE 08:00 A 14:00 HORAS', '29 JUNIO 2026 AL 26 OCTUBRE 2026', '2026-08-05'::DATE, NULL, '2026-08-05'::DATE, 'P.A090/2026', '2026-06-06'::DATE, '2026-08-13'::DATE, NULL, 'SI'::dictamen_academia_enum, 41, 'LORENA MARGARITA VAZQUEZ OCHOA', NULL, 'P.B100/2026', '2026-08-13'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(84, '20071355', 'Ene-Jun 2026', 'DISEÑO DE UN PROGRAMA DE
MANTENIMIENTO PREVENTIVO PARA EL
PARQUE VEHICULAR DE PESADO
TRANSPORT EN ESEASA', 40, 'EQUIPOS ESPECIALIZADOS OFFSHORE, DIVISIÓN SERVICIOS S.C.', 'LIC. DENISSE ARISBED ARMENTA ARENAS', 'DE 08:00 A 18:00 HORAS', '17 ABRIL 2026 AL 15 AGOSTO 2026', '2026-08-05'::DATE, NULL, '2026-08-05'::DATE, 'P.A091/2026', '2026-09-09'::DATE, '2026-09-11'::DATE, NULL, 'SI'::dictamen_academia_enum, 19, 'Jose Refuguio Hernandez Mendoza', '26-1-2', 'P.B101/2026', '2026-09-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(85, '19070353', 'Ene-Jun 2026', 'IMPLEMENTACION DE UN PROGRAMA DE CONTROL DE RIESGOS LABORALES EN EL TALLER DE FABRICACION DE ANSA INGENIERIA', 12, 'ANSA INGENIERIA Y CONTROL', 'LIC. YOSELIN DEL ANGEL CERON', 'DE 08:00 A 18:00 HORAS', '01 ABRIL 2026 AL 01 AGOSTO 2026', '2026-08-05'::DATE, NULL, '2026-08-05'::DATE, 'P.A092/2026', '2026-09-07'::DATE, '2026-09-11'::DATE, NULL, 'SI'::dictamen_academia_enum, 25, 'Orlando Merinos', '26-1-2', 'P.B102/2026', '2026-09-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(86, '24070164', 'Ene-Jun 2026', 'ANALISIS DE LA EFICIENCIA ENERGETICA E IDENTIFICACION DE CAUSAS DE DESVIACION DEL DESEMPEÑO ENERGETICO EN EL CPG ARENQUE 2025', 28, 'COMPLEJO PROCESADOR DE GAS ARENQUE', 'ING. GUADALUPE EDU GONZÁLEZ ROCHA', 'DE 08:00 A 14:00 HORAS', '15 JUNIO 2026 AL 09 OCTUBRE 2026', '2026-08-17'::DATE, NULL, NULL, 'P.A093/2026', '2026-10-15'::DATE, '2026-10-16'::DATE, NULL, 'Pendiente'::dictamen_academia_enum, 27, 'JUAN FLAVIO MOLAR OROZCO', NULL, 'P.B103/2026', '2026-10-16'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(87, '21071519', 'Ene-Jun 2026', 'PROPUESTA DE MEJORA ERGONOMICA Y DE SEGURIDAD EN LAS AREAS DE RECURSOS HUMANOS Y FACTURACION DE NISSAN MADERO', 70, 'NISSAN MADERO', 'LIC. ALEJANDRO PANIAGUA MACÍAS', 'DE 08:00 A 14:00 HORAS', '10 MARZO 2026 AL 10 SEPTIEMBRE 2026', '2026-08-17'::DATE, NULL, '2026-08-17'::DATE, 'P.A094/2026', '2026-08-26'::DATE, '2026-09-01'::DATE, NULL, 'SI'::dictamen_academia_enum, 29, 'VIRGINIA OLIVARES', '26-2-1', 'P.B104/2026', '2026-09-18'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(88, '20070240', 'Ene-Jun 2026', 'PROPUESTA DE MEJORA DE LA SEGURIDAD DE LAS INSTALACIONES PORTUARIAS DE LA TERMINAL MARITIMA MADERO PARA EL CUMPLIMIENTO DEL CODIGO PBIP', 73, 'PEMEX LOGISTICA TASP MADERO', 'LIC. JESÚS EMMANUEL RODRÍGUEZ RODRÍGUEZ', 'DE 08:00 A 14:00 HORAS', '18 MAYO 2026 AL 10 SEPTIEMBRE 2026', '2026-08-17'::DATE, NULL, '2026-08-17'::DATE, 'P.A095/2026', '2026-08-26'::DATE, '2026-09-02'::DATE, NULL, 'SI'::dictamen_academia_enum, 40, 'ARTURO VAZQUEZ LARA', '26-2-1', 'P.B105/2026', '2026-09-02'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(89, '21071088', 'Ene-Jun 2026', 'DESARROLLO DE UN MANUAL DE ERGONOMIA Y SEGURIDAD PARA LA PREVENCION DE RIESGOS LABORALES EN LA PLANTA
HILDAGAS', 42, 'GASIFICADORA DEL GOLFO S de R.L. DE C.V.', 'ING. JORGE LUIS ARTEAGA NIETO', 'DE 07:00 A 14:00 HORAS', '02 FEBRERO 2026 AL 12 JUNIO 2026', '2026-08-25'::DATE, NULL, '2026-08-25'::DATE, 'P.A096/2026', '2026-09-04'::DATE, '2026-09-11'::DATE, NULL, 'SI'::dictamen_academia_enum, 7, 'SUSANA PATRICIA ESCOBAR PINEDA', '26-2-1', 'P.B106/2026', '2026-09-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(90, '22070075', 'Ene-Jun 2026', 'IMPLEMENTACION DE LA METODOLOGIA 5S EN LAS AREAS DE TRABAJO GEMA
CAPACITACION Y CONSULTORIA HSEQ', 44, 'GEMA CAPACITACION Y CONSULTORIA HSEQ', 'ING. ESTEBAN CARLOS GONZALEZ FUENTES', 'DE 09:00 A 15:00 HORAS', '01 JUNIO 2026 AL 06 NOVIEMBRE 2026', '2026-08-25'::DATE, NULL, '2026-08-25'::DATE, 'P.A097/2026', '2026-09-09'::DATE, '2026-09-11'::DATE, NULL, 'SI'::dictamen_academia_enum, 34, 'CESAR DAVID RIVERA TOSCANO', '26-2-1', 'P.B107/2026', '2026-09-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(91, '20071261', 'Ene-Jun 2026', 'IMPLEMENTACION DE METODOLOGIA 5S EN EL DEPARTAMENTO ADMINISTRATIVO DE LA EMPRESA COMISION FEDERAL DE ELECTRICIDAD', 27, 'COMISIÓN FEDERAL DE ELECTRICIDAD', 'ING. NORMA NAYELI HERRERA ESCOBAR', 'DE 08:00 A 16:00 HORAS', '21 ABRIL 2026 AL 21 AGOSTO 2026', '2026-08-27'::DATE, NULL, '2026-08-27'::DATE, 'P.A098/2026', '2026-09-03'::DATE, '2026-09-07'::DATE, NULL, 'SI'::dictamen_academia_enum, 42, 'MARGARITA ZAVALA ARCE', '26-2-1', 'P.B108/2026', '2026-09-07'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(92, '20071305', 'Ene-Jun 2026', 'INTEGRACION DEL PROCESO DE ENSAMBLE DEL ACTUADOR SC36 A LA LINEA DE FAMILIA DE SERVICE CHAMBERS EN CELDA 7 MEDIANTE EL DESARROLLO E IMPLEMENTACION DE CORE TOOLS', 54, 'HALDEX PRODUCTS DE MEXICO', 'ING. ALAN ARTURO MORALES MARTÍNEZ', 'DE 07:00 A 15:30 HORAS', '01 JUNIO 2026 AL 30 NOVIEMBRE 2026', '2026-08-31'::DATE, NULL, '2026-09-01'::DATE, 'P.A099/2026', '2026-09-03'::DATE, '2026-09-07'::DATE, '2026-09-07'::DATE, 'SI'::dictamen_academia_enum, 27, 'JUAN FLAVIO MOLAR OROZCO', '26-2-1', 'P.B109/2026', '2026-09-07'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(93, '20071356', 'Ene-Jun 2025', 'GUIA PARA EL PROCESO DE LA INVESTIGACION DE CONDICIONES DE MERCADO (ICM) EN EL AREA ESPECIALIZADA DE INTELIGENCIA DE MERCADO', 24, 'CFE DISTRIBUCION', 'ING. ANA KAREN SOLIS CHAVEZ', 'DE 8:00 A 13:00 HORAS', '03 ABRIL 2025 AL 03 SEPTIEMBRE 2025', NULL, 'REASIGNACIÓN', NULL, 'P.A106/2025', '2026-08-27'::DATE, '2026-09-02'::DATE, NULL, 'NO'::dictamen_academia_enum, 18, 'JOSE ALVARO GUTIERREZ TREVIÑO', NULL, 'P.B001/2025', '2026-09-02'::DATE, 'Caso Especial / Reasignación'::estado_expediente_enum, 'Reasignación de proyecto/asesor'),
(94, '20071358', 'Ene-Jun 2026', 'DETERMINACION DE LOS TIEMPOS ESTANDAR DE LAS ACTIVIDADES DEL PERSONAL EN EL PROCESO DE PRODUCCION DE HIPOCLORITO DE SODIO EN LA EMPRESA MISHUE CONCENTRADORA', 68, 'MISHUE CONCENTRADORA', 'C.P. CAMILO GABRIEL CHEIN SCHEKAIBAN', 'DE 09:00 A 14:00 HORAS', '30 MARZO 2026 AL 30 SEPTIEMBRE 2026', '2026-09-02'::DATE, NULL, '2026-09-02'::DATE, 'P.A100/2026', '2026-09-04'::DATE, '2026-09-11'::DATE, NULL, 'SI'::dictamen_academia_enum, 1, 'ENEDINA ALVAREZ CRUZ', '26-2-1', 'P.B110/2026', '2026-09-11'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(95, '22070856', 'Ene-Jun 2026', 'DISEÑO, MODELADO E IMPLEMENTACION DE MINERIA DE PROCESOS APLICADO A LA LOGISTICA DE LA INFORMACION EN LAS OPERACIONES DE LA DIRECCION DE FINANZAS Y CONTRALORIA EN GT GLOBAL', 52, 'GRUPO TAMPICO', 'LIC. RUBEN FIGUEROA ESTAÑOL', 'DE 09:00 A 18:00 HORAS', '23 MARZO 2026 AL 23 JULIO 2026', '2026-09-09'::DATE, NULL, '2026-09-11'::DATE, 'P.A101/2026', '2026-09-24'::DATE, '2026-09-29'::DATE, NULL, 'Si'::dictamen_academia_enum, 25, 'ERICK ORLANDO MERINOS HERRERA', '26-2-1', 'P.B111/2026', '2026-09-29'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(96, '22070879', 'Ago-Dic 2026', 'DISEÑO DE UN SISTEMA PARA EL DESARROLLO DE PRESENTACIONES, CURSOS Y TALLERES  DE CAPACITACION', 26, 'COMERCIALIZADORA E INTEGRADORA DE PRODUCTOS Y SERVICIOS GEMA,S.A. DE C.V.', 'ING. ESTEBAN CARLOS GONZALEZ', 'DE 09:00 A 15:0O HORAS', '19 AGOSTO AL 19 DICIEMBRE 2026', '2026-09-17'::DATE, NULL, '2026-09-18'::DATE, 'P.A102/2026', '2026-09-22'::DATE, '2026-09-23'::DATE, NULL, 'SI'::dictamen_academia_enum, 27, 'JUAN FLAVIO MOLAR OROZCO', '26-2-2', 'P.B112/2026', '2026-09-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(97, '22070817', 'Ago-Dic 2026', 'VERIFICACION DE LA CONFORMIDAD DE LOS INSTRUMENTOS DE EVALUACION UTILIZADOS POR CONSULTORA GISMMA RESPECTO A LAS NORMAS OFICIALES MEXICANAS DE LA STPS', 35, 'CONSULTORÍA GISMMA S.A. DE C.V.', 'ING. EMMANUEL TOMAS CRUZ', 'DE 09:00 A 18:00 HORAS', '09 SEPTIEMBRE 2026 AL 09 ENERO 2027', '2026-09-17'::DATE, NULL, '2026-09-18'::DATE, 'P.A103/2026', '2026-09-22'::DATE, '2026-09-23'::DATE, NULL, 'SI'::dictamen_academia_enum, 20, 'VERONICA HERNANDEZ MORALES', '26-2-1', 'P.B113/2026', '2026-09-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(98, '21071100', 'Ene-Jun 2026', 'DISEÑO DE UN SISTEMA DE CONTROL OPERACIONAL PARA PRODUCTOS REPRESENTATIVOS DE GRUPO PIC MEDIANTE LA ELABORACION DE PROCEDIMIENTOS OPERATIVOS ESTANDARIZADOS (SOP), HOJAS DE INSTRUCCION VISUAL (ITV) Y LISTAS DE VERIFICACION', 21, 'CASER PROYECTOS', 'LIC. JESUS GABRIEL HERBERT CAMARILLO', 'DE 09:00 A 18:00 HORAS', '25 MAYO 2026 AL 25 NOVIEMBRE 2026', '2026-09-18'::DATE, NULL, '2026-09-18'::DATE, 'P.A104/2026', '2026-09-22'::DATE, '2026-09-23'::DATE, NULL, 'SI'::dictamen_academia_enum, 22, 'JOSE LUIS LUCIO SILVA', '26-2-1', 'P.B114/2026', '2026-09-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(99, '22070806', 'Ago-Dic 2026', 'ANALISIS Y DISEÑO DE UN PROGRAMA DE SEGURIDAD OPERATIVA PARA LAS HERRAMIENTAS, EQUIPOS DE SOLDADURA Y ANDAMIAJES EN OBRA MECANICA', 14, 'ARAC DE LA SULTANA S.A. DE C.V.', 'ING. GABRIEL ANGEL PIÑEIRO PARADA', 'DE 08:00 A 18:00 HORAS', '07 SEPTIEMBRE 2026 AL 07 ENERO 2027', '2026-09-18'::DATE, NULL, '2026-09-18'::DATE, 'P.A105/2026', '2026-09-25'::DATE, '2026-09-29'::DATE, NULL, 'SI'::dictamen_academia_enum, 25, 'ORLANDO MERINOS', '26-2-1', 'P.B115/2026', '2026-09-29'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(100, '22070737', 'Ago-Dic 2026', 'ELABORACION DE UNA GUIA DE PROCESOS DE CAPACITACION EN LA EMPRESA SUMINISTROS Y CONSULTORIA PUNTA SUR', 26, 'COMERCIALIZADORA E INTEGRADORA DE PRODUCTOS Y SERVICIOS GEMA,S.A. DE C.V.', 'ING. ESTEBAN CARLOS GONZALEZ FUENTES', 'DE 09:00 A 15:00 HORAS', '03 AGOSTO 2026 AL 03 DICIEMBRE 2026', '2026-09-18'::DATE, NULL, '2026-09-18'::DATE, 'P.A106/2026', '2026-09-25'::DATE, '2026-09-29'::DATE, NULL, 'SI'::dictamen_academia_enum, 24, 'CARLOS EUSEBIO MAR OROZCO', '26-2-1', 'P.B116/2026', '2026-09-29'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(101, '22070799', 'Ago-Dic 2026', 'PROPUESTA DE MEJORA CON BASE AL SEGUIMIENTO Y ANALISIS DE LOS OKR´s DEL PERSONAL DE ENERTEK', 75, 'QUANTUM ENERGIA', 'ING. FRANCISCO FELICIANO GONZÁLEZ LÓPEZ', 'DE 08:00 A 16:00 HORAS', '31 AGOSTO 2026 AL 31 DICIEMBRE 2026', '2026-09-21'::DATE, NULL, '2026-09-21'::DATE, 'P.A107/2026', '2026-09-22'::DATE, '2026-09-23'::DATE, NULL, 'SI'::dictamen_academia_enum, 21, 'RICARDO LOPEZ DE LARA GONZALEZ', '26-2-1', 'P.B117/2026', '2026-09-23'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(102, '22070893', 'Ago-Dic 2026', 'EVALUACION DEL DESEMPEÑO DEL PERSONAL MECANICO DE LA EMPRESA COBSA MEDIANTE EL ANALISIS, SEGUIMIENTO Y CONTROL DE LAS ORDENES DE TRABAJO UTILIZANDO INDICADORES DE DESEMPEÑO', 32, 'CONSULTORIA EN OBRA S.A. DE C.V.', 'ING. ENRIQUE ALEJANDRO FLORES LOPEZ', 'DE 08:00 A 17:00 HORAS', '04 SEPTIEMBRE 2026 AL 04 ENERO 2027', '2026-09-21'::DATE, NULL, '2026-09-21'::DATE, 'P.A108/2026', '2026-09-24'::DATE, '2026-09-29'::DATE, NULL, 'SI'::dictamen_academia_enum, 17, 'ANGELA AURORA GUTIÉRREZ SALAS', '26-2-1', 'P.B118/2026', '2026-09-29'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(103, '22070842', 'Ago-Dic 2026', 'OPTIMIZACION DEL PROCESO LOGISTICO DE ADQUISICION Y ABASTECIMIENTO DE REFACCIONES, PIEZAS Y MATERIALES EN EL AREA DE MAQUINARIA Y EQUIPO DE LA EMPRESA COBSA', 32, 'CONSULTORIA EN OBRA S.A. DE C.V.', 'ING. ENRIQUE ALEJANDRO FLORES LOPEZ', 'DE 08:00 A 15:00 HORAS', '04 SEPTIEMBRE 2026 AL 04 ENERO 2027', '2026-09-21'::DATE, NULL, '2026-09-21'::DATE, 'P.A109/2026', '2026-09-24'::DATE, '2026-09-29'::DATE, NULL, 'SI'::dictamen_academia_enum, 28, 'RUBEN MORENO SALAZAR', '26-2-1', 'P.B119/2026', '2026-09-29'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(104, '22070873', 'Ago-Dic 2026', 'DISEÑO DE LOS SISTEMAS DE RECEPCION Y ENTREGA PARA LOS DIFERENTES TIPOS DE TRANSPORTE EN LOS ALMACENES', 55, 'INDELPRO', 'C.P. GUSTAVO ENRIQUE HERNÁNDEZ BRIONES', 'DE 08:00 A 17:30 HORAS', '17 DE AGOSTO 2026 AL 17 DE ENERO 2027', '2026-09-22'::DATE, NULL, '2026-09-21'::DATE, 'P.A110/2026', '2026-09-30'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 33, 'LINDA ISABEL QUILANTAN MELIAN', '26-2-1', 'P.B120/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(105, '20071315', 'Ene-Jun 2026', 'IMPLEMENTACION DE LA METOLOGIA 5S PARA LA OPTIMIZACION DEL ESPACIO Y LAS CONDICIONES DE TRABAJO EN INMOBILIARIA MORAN', 59, 'INMOBILIARIA MORAN', 'LIC. EMMANUEL MORAN MARTINEZ', 'DE 08:00 A 18:00 HORAS', '16 MARZO 2026 AL 16 SEPTIEMBRE 2026', '2026-09-22'::DATE, NULL, '2026-09-12'::DATE, 'P.A111/2026', '2026-09-24'::DATE, '2026-09-29'::DATE, NULL, 'SI'::dictamen_academia_enum, 3, 'BLANCA NELVA CASTILLO BOLAÑOS', '26-2-1', 'P.B121/2026', '2026-09-29'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(106, '22071327', 'Ago-Dic 2026', 'ANALISIS Y PROPUESTA DE MEJORA PARA LOS PROCESOS DEL DEPARTAMENTO DE FINANZAS QUE GENERAN DOCUMENTOS FISICOS PARA SU RESGUARDO', 95, 'VESTOLIT', 'C.P. BERENICE MARTINEZ PIERDANT', 'DE 08:00 A 15:00 HORAS', '15 DE AGOSTO 2026 AL 15 DE ENERO 2027', '2026-09-23'::DATE, NULL, '2026-09-24'::DATE, 'P.A112/2026', '2026-09-30'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 11, 'JORGE DANIEL GALVAN NARVAEZ', '26-2-1', 'P.B122/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(107, '22070839', 'Ago-Dic 2026', 'DISEÑO DE UN SISTEMA PARA LA LOCALIZACION DE TUBERIA DESTINADA AL SUMINISTRO DE AGUA A PLANTAS DEL CORREDOR INDUSTRIAL', 6, 'AGUILA MANTENIMIENTO INDUSTRIAL,S.A. DE C.V.', 'ING. JUAN FRANCISCO MAYA PEÑA', 'DE 08:00 A 18:00 HORAS', '03 AGOSTO 2026 AL 03 DICIEMBRE 2026', '2026-09-24'::DATE, NULL, '2026-09-24'::DATE, 'P.A113/2026', '2026-09-30'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 32, 'VICTOR MANUEL QUILANTAN GARZA', '26-2-1', 'P.B123/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(108, '21070886', 'Ago-Dic 2026', 'OPTIMIZACION DEL PROCESO DE CONTROL DOCUMENTAL Y REGISTRO DE OPERACIONES DE IMPORTACION Y EXPORTACION EN AGENCIA ADUANAL GEREZ', 50, 'GRUPO GEREZ', 'LIC. CRISTINA GUADALUPE RAMÍREZ RODRÍGUEZ', 'DE 09:00 A 13:00 HORAS', '19 AGOSTO 2026 AL 10 ENERO 2027', '2026-09-24'::DATE, NULL, '2026-09-24'::DATE, 'P.A114/2026', '2026-10-01'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 2, 'ALFONSO BARBOSA MORENO', '26-2-1', 'P.B124/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(109, '22070726', 'Ago-Dic 2026', 'DISEÑO Y DESARROLLO DE UN SISTEMA PARA LA MEDICION, CONTROL Y SEGUIMIENTO DEL AVANCE DEL PLAN ANUAL DE MANTENIMIENTO MEDIANTE POWER BI', 87, 'SOCIEDAD NACIONAL PROMOTORA DE BECARIOS S.C.', 'LIC. KRISTOV DANIEL FUENTES NOLASCO', 'DE 08:00 A 14:00 HORAS', '08 SEPTIEMBRE 2026 AL 08 ENERO 2027', '2026-09-25'::DATE, NULL, '2026-09-25'::DATE, 'P.A115/2026', '2026-10-09'::DATE, '2026-10-14'::DATE, NULL, 'SI'::dictamen_academia_enum, 38, 'ROBERTO JESUS TREVIÑO VALENZUELA', '26-2-1', 'P.B125/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(110, '22070740', 'Ago-Dic 2026', 'OPTIMIZACION DEL CONTROL Y SEGUIMIENTO DE REQUERIMIENTOS DE MATERIALES MEDIANTE INDICADORES DE DESEMPEÑO EN UNA EMPRESA CONSTRUCTORA DE LA REGION', 32, 'CONSULTORIA EN OBRA S.A. DE C.V.', 'ING. ARELY CARRIZALES DEANTES', 'DE 8:30 A 17:30 HORAS', '24 AGOSTO 2026 AL 24 DICIEMBRE 2026', '2026-09-25'::DATE, NULL, '2026-09-25'::DATE, 'P.A116/2026', '2026-10-01'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 41, 'LORENA MARGARITA VAZQUEZ OCHOA', '26-2-1', 'P.B126/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(111, '22070828', 'Ago-Dic 2026', 'ANALISIS Y MEJORA DEL CONTROL Y SEGUIMIENTO DE LOS PROCESOS EN EL DEPARTAMENTO DE CALIDAD MEDIANTE HERRAMIENTAS DE MEJORA CONTINUA', 51, 'GRUPO INDUSTRIAL AGUILA S.A. DE C.V.', 'ING. FRANCISCO JAVIER TELLEZ CARDIEL', 'DE 08:00 A 12:00 HORAS', '3 DE AGOSTO AL 3 DE DICIEMBRE DE 2026', '2026-09-28'::DATE, NULL, '2026-09-28'::DATE, 'P.A117/2026', '2026-10-01'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 4, 'CAROLINA CONTRERAS ALVAREZ', '26-2-1', 'P.B127/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(112, '22070807', 'Ago-Dic 2026', 'ANALISIS Y MEJORA DEL SISTEMA DE COTIZACION PARA LA GESTION DE EQUIPOS Y TARIFAS DE RENTA EN RENT CO.', 77, 'RENTCO CONSTRUCCIÓN & MACHINERY, S.A. DE C.V.', 'LIC. MARTHA PATRICIA TORRES MARTÍNEZ', 'DE 08:00 A 14:00 HORAS', '31 DE AGOSTO 2026 AL 6 DE ENERO 2027', '2026-09-28'::DATE, NULL, '2026-09-28'::DATE, 'P.A118/2026', '2026-10-01'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 10, 'JORGE ALBERTO GALVEZ CHOY', '26-2-1', 'P.B128/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(113, '21071032', 'Ene-Jun 2026', 'ANALISIS Y PROPUESTA DE MEJORA DEL PROCESO DE CARGA Y DESCARGA DE UNIDADES DE REPARTO EN EL CEDIS BIMBO , APLICANDO LA METODOLOGIA 8D PARA LA REDUCCION DE MERMAS Y DAÑOS FISICOS', 47, 'GRUPO BIMBO', 'LIC. LUIS ENRIQUE MARTÍNEZ LARZA', 'DE 07:00 A 15:00 HORAS', '10 DE AGOSTO AL 10 DE DICIEMBRE DE 2026', '2026-09-28'::DATE, NULL, '2026-09-28'::DATE, 'P.A119/2026', '2026-10-01'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 9, 'Ma Elena García Alvarado', '26-2-1', 'P.B129/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(114, '22070744', 'Ago-Dic 2026', 'DISEÑO DEL SISTEMA DE GESTION PARA LA IMPLEMENTACION DE LA ISO/IEC 17025 EN UN LABORATORIO', 97, 'WELDING & COATING LAB (OSCAR PADRÓN DOMÍNGUEZ)', 'ING. OSCAR PADRÓN DOMÍNGUEZ', 'DE 08:00 A 14:00 HORAS', '31 DE AGOSTO DE 2026 AL 6 DE ENERO 2027', '2026-09-28'::DATE, NULL, '2026-09-28'::DATE, 'P.A120/2026', '2026-10-01'::DATE, '2026-10-06'::DATE, NULL, 'SI'::dictamen_academia_enum, 5, 'MARGARITA CONTRERAS MATA', '26-2-1', 'P.B130/2026', '2026-10-06'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(115, '22070748', 'Ago-Dic 2026', 'ESTRUCTURACION Y ACTUALIZACION DEL MANUAL TECNICO DE IDENTIFICACION DE DAÑOS A CONTENEDORES EN ALIANZA ESTRATEGICA PORTUARIA EN AREA DE PIV', 46, 'GRUPO ALIANZA ESTRATEGICA PORTUARIA', 'ING. RODRIGO ALEJANDRO ROBLES JIMENEZ', 'DE 8:30 A 14:00 HORAS', '17 DE AGOSTO 2026 AL 01 DE MARZO 2027', '2026-09-28'::DATE, NULL, '2026-10-09'::DATE, 'P.A137/2026', NULL, NULL, NULL, 'SI'::dictamen_academia_enum, 6, 'JUAN CARLOS ESPINOZA VELASCO', '26-2-1', 'P.B131/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(116, '21070922', 'Ago-Dic 2026', 'IMPLEMENTACION DE EQUIPO KEYENCE PARA ASEGURAR EL CORRECTO ENSAMBLE DE LA CAMARA DE REVERSA EN VEHICULOS', 17, 'BMW GROUP PLANTA SAN LUIS POTOSI', 'LIC. LORENA ELIZABETH VARGAS ORTEGA', 'DE 07:00 A 14:30 HORAS', '26 DE JUNIO 2026 AL 26 DE NOVIEMBRE 2026', '2026-09-28'::DATE, NULL, '2026-09-29'::DATE, 'P.A122/2026', '2026-10-06'::DATE, '2026-10-13'::DATE, NULL, 'SI'::dictamen_academia_enum, 34, 'M.I.A. CESAR DAVID RIVERA TOSCANO', '26-2-2', 'P.B132/2026', '2026-10-13'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(117, '22070790', 'Ago-Dic 2026', 'PREPARACION DE LA TRANSICION DEL SISTEMA DE GESTION DE CALIDAD DE DYNASOL MEXICO DE LA NORMA ISO 9001:2015 A LA NORMA ISO 9001:2026', 38, 'DYNASOL', 'ING. MARCIAL CARBALLO LOREDO', 'DE 08:00 A 12:00 HORAS', '21 AGOSTO 2026 AL 31 ENERO 2027', '2026-09-28'::DATE, NULL, '2026-09-29'::DATE, 'P.A123/2026', '2026-10-06'::DATE, '2026-10-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 31, 'GUILLERMO PEÑA GARCÍA', '26-2-1', 'P.B133/2026', '2026-10-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(118, '22070838', 'Ago-Dic 2026', 'EVALUACION, ANALISIS Y PROPUESTA DE MEJORA INTEGRAL DE LAS CONDICIONES DE SEGURIDAD INDUSTRIAL MEDIANTE LA IDENTIFICACION Y CONTROL DE RIESGOS LABORALES EN LAS AREAS DE MANTENIMIENTO Y REPARACION DE CAMIONES', 39, 'ENER MANTENIMIENTO INTEGRAL S.A. DE C.V.', 'ING. CARLOS RAFAEL CAPACHA', 'DE 8:30 A 18:00 HORAS', '10 SEPTIEMBRE 2026 AL 11 ENERO 2027', '2026-09-28'::DATE, NULL, '2026-09-29'::DATE, 'P.A124/2026', '2026-10-06'::DATE, '2026-10-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 35, 'ARMANDO RONZON CAMPOS', '26-2-1', 'P.B134/2026', '2026-10-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(119, '21070959', 'Ago-Dic 2026', 'DISEÑO DEL SISTEMA DE REPORTES DE SINIESTRALIDAD EN TIENDAS CHEDRAUI REGION NORESTE', 92, 'TIENDAS CHEDRAUI, S.A. DE C.V.', 'LIC. ELVIRA VADILLO ALMAZÁN', 'DE 09:00 A 14:00 HRS', '10 DE SEPTIEMBRE 2026 AL 29 DE ENERO 2027', '2026-09-30'::DATE, NULL, '2026-10-01'::DATE, 'P.A125/2026', '2026-10-06'::DATE, '2026-10-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 19, 'Jose Refuguio Hernandez Mendoza', '26-2-1', 'P.B135/2026', '2026-10-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(120, '21071115', 'Ago-Dic 2025', 'OPTIMIZACION DE LOS FLUJOS DE TRABAJO ADMINISTRATIVOS Y COTROL OPERATIVO EN LA COORDINACIÓN DE RH MULTISUCURSAL UTILIZANDO INDICADORES DE DESEMPEÑO', 91, 'TIENDAS CHEDRAUI S.A. DE C.V.', 'LIC. CLARA ELIZABETH ROCHA ARELLANO', 'DE 08:00 A 15:00 HORAS', '18 SEPTIEMBRE 2026 AL 25 ENERO 2027', '2026-09-30'::DATE, NULL, '2026-10-01'::DATE, 'P.A126/2026', '2026-10-06'::DATE, '2026-10-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 36, 'PEDRO RODRIGUEZ PITON', '26-2-1', 'P.B136/2026', '2026-10-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(121, '21071515', 'Ene-Jun 2026', 'EVALUACION DE LA ERGONOMIA EN LOS PUESTOS DE TRABAJO DE GRUPO GAREL MEDIANTE LA METODOLOGIA RULA', 83, 'SERVICIOS PROFESIONALES GGA S.A. DE C.V.', 'LIC. ISKRA ZORAIDA PAEZ TANGUMA', 'DE 09:00 A 14:00 HORAS', '02 ABRIL 2026 AL 02 OCTUBRE 2026', '2026-09-30'::DATE, NULL, '2026-10-01'::DATE, 'P.A127/2026', '2026-10-06'::DATE, '2026-10-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 16, 'MARIA CRISTINA GUERRERO RODRIGUEZ', '26-2-1', 'P.B137/2026', '2026-10-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(122, '21071109', 'Ago-Dic 2026', 'DISEÑO DE UN SISTEMA DE CONTROL Y SEGUIMIENTO DE ACTIVIDADES OPERATIVAS PORTUARIAS EN LA AGENCIA CONSIGNATARIA DEL GOLFO S.A. DE C.V.', 3, 'AGENCIA CONSIGNATARIA DEL GOLFO S.A. DE C.V.', 'ING. ANÍBAL ROGELIO DE LA CRUZ CEDILLO', 'DE 08:00 A 16:00 HORAS', '07 SEPTIEMBRE 2026 AL 07 ENERO 2027', '2026-10-01'::DATE, NULL, '2026-10-01'::DATE, 'P.A128/2026', '2026-10-06'::DATE, '2026-10-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 14, 'BERNARDO GOLDARACENA OTERO', '26-2-1', 'P.B138/2026', '2026-10-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(123, '21071106', 'Ago-Dic 2026', 'PROPUESTA DE UN MODELO DE GESTION DE MANTENIMIENTO VEHICULAR PARA EL TRANSPORTE DE RESIDUOS DE MANEJO ESPECIAL EN LA EMPRESA SOS SOLUCIONES SOSTENIBLES', 89, 'SOS SOLUCIONES SOSTENIBLES', 'ING. ALFREDO BAUTISTA HERNANDEZ', 'DE 09:00 A 15:00 HORAS', '11 SEPTIEMBRE 2026 AL 11 ENERO 2026', '2026-10-01'::DATE, NULL, '2026-10-01'::DATE, 'P.A129/2026', '2026-10-06'::DATE, '2026-10-09'::DATE, NULL, 'SI'::dictamen_academia_enum, 12, 'FRANCISCO EDUARDO GIRON FLORES', '26-2-1', 'P.B139/2026', '2026-10-09'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(124, '22070749', 'Ago-Dic 2026', 'EVALUACION Y OPTIMIZACION DE LAS HORAS HOMBRE POR JORNADA LABORAL MEDIANTE MAPEO DE PROCESO EN EL DEPARTAMENTO MECANICO DE LA CENTRAL TERMOELECTRICA ALTAMIRA', 23, 'CFE CENTRAL TERMOELÉCTRICA DE ALTAMIRA', 'ING. JUAN MANUEL LULE GARCÍA', 'DE 08:00 A 15:30 HORAS', '21 SEPTIEMBRE 2026 AL 21 ENERO 2027', '2026-10-02'::DATE, NULL, '2026-10-05'::DATE, 'P.A130/2026', '2026-10-09'::DATE, '2026-10-14'::DATE, NULL, 'SI'::dictamen_academia_enum, 37, 'FRANCISCO JAVIER SILVA COBOS', '26-2-1', 'P.B140/2026', '2026-10-14'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(125, '22071201', 'Ago-Dic 2026', 'ANALISIS DE LA INFORMACION CRITICA EN LA CADENA DE VALOR PARA LA MEJORA CONTINUA EN EL DEPARTAMENTO DE INTERMEDIACION DE CONTRATOS LEGADOS DE CFE', 27, 'COMISIÓN FEDERAL DE ELECTRICIDAD', 'ING. EDUARDO GONZÁLEZ LUGO', 'DE 09:00 A 15:00 HORAS', '14 SEPTIEMBRE 2026 AL 14 ENERO 2027', '2026-10-02'::DATE, NULL, '2026-10-05'::DATE, 'P.A131/2026', '2026-10-09'::DATE, '2026-10-14'::DATE, NULL, 'SI'::dictamen_academia_enum, 33, 'LINDA ISABEL QUILANTAN MELIAN', '26-2-2', 'P.B141/2026', '2026-10-14'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(126, '22070741', 'Ago-Dic 2026', 'MODELO DE CRECIMIENTO', 67, 'MEXICHEM RESINAS VINILICAS S.A. DE C.V.', 'ING. MARTHA OFELIA MERCADO GONZALEZ', 'DE 08:00 A 15:00 HORAS', '01 SEPTIEMBRE 2026 AL 11 ENERO 2027', '2026-10-02'::DATE, NULL, '2026-10-05'::DATE, 'P.A132/2026', '2026-10-09'::DATE, '2026-10-14'::DATE, NULL, 'SI'::dictamen_academia_enum, 10, 'JORGE ALBERTO GALVEZ CHOY', '26-2-2', 'P.B142/2026', '2026-10-14'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(127, '22070822', 'Ago-Dic 2026', 'ANALISIS Y BALANCEO DE CARGAS DE TRABAJO DEL PERSONAL DE SERVICIOS GENERALES DE LA BENEFICIENCIA ESPAÑOLA', 22, 'CENTRO ESPAÑOL DE TAMPICO A.C.', 'LIC. JOSÉ LUIS LUNA RIVERA', 'DE 08:00 A 12:00 HORAS', '31 AGOSTO 2026 AL 26 FEBRERO 2027', '2026-10-05'::DATE, NULL, '2026-10-05'::DATE, 'P.A133/2026', '2026-10-09'::DATE, '2026-10-14'::DATE, NULL, 'SI'::dictamen_academia_enum, 1, 'ENEDINA ALVAREZ CRUZ', '26-2-2', 'P.B143/2026', '2026-10-14'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(128, '22070791', 'Ago-Dic 2026', 'DISEÑO DE UN PLAN DE MANTENIMIENTO PREVENTIVO PARA EL SISTEMA DE BOMBAS DE AMINA EN LA PLANTA ENDULZADORA DEL CPG ARENQUE', 74, 'PETROLEOS MEXICANOS', 'ING. JORGE DENEB LOPEZ GONZALEZ', 'DE 08:00 A 14:00 HORAS', '21 SEPTIEMBRE 2026 AL 21 ENERO 2027', '2026-10-05'::DATE, NULL, '2026-10-05'::DATE, 'P.A134/2026', '2026-10-09'::DATE, '2026-10-14'::DATE, NULL, 'SI'::dictamen_academia_enum, 24, 'CARLOS EUSEBIO MAR OROZCO', '26-2-2', 'P.B144/2026', '2026-10-14'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(129, '22070947', 'Ago-Dic 2026', 'DISEÑO DE UN PLAN DE CONTROL DOCUMENTAL MEDIANTE HERRAMIENTAS DE INGENIERÍA INDUSTRIAL QUE PERMITA MEJORAR LA ORGANIZACIÓN, SEGUIMIENTO Y GESTION DE LOS EXPEDIENTES DE INSPECCION TECNICA EN EL COMPLEJO PROCESADOR DE GAS ARENQUE', 74, 'PETROLEOS MEXICANOS', 'ING. JOSÉ LUIS GAZCA SÁNCHEZ', 'DE 08:00 A 14:00 HORAS', '21 SEPTIEMBRE 2026 AL 21 ENERO 2027', '2026-10-06'::DATE, NULL, '2026-10-06'::DATE, 'P.A135/2026', '2026-10-09'::DATE, '2026-10-14'::DATE, NULL, 'SI'::dictamen_academia_enum, 39, 'BRENDA JASSIVE TORRES GONZALEZ', '26-2-1', 'P.B145/2026', '2026-10-14'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(130, '20071416', 'Ene-Jun 2026', 'ANALISIS DE MEJORA DEL SISTEMA DE RUTEO PARA LA TOMA DE LECTURA DE CICLOS PARES AGENCIA TAMPICO', 27, 'COMISIÓN FEDERAL DE ELECTRICIDAD', 'ING. ARTURO RODRIGUEZ TRINIDAD', 'DE 8:00 A 13:00 HORAS', '23 DE FEBRERO AL 22 DE JUNIO 2026', '2026-10-09'::DATE, NULL, '2026-10-09'::DATE, 'P.A136/2026', '2026-10-15'::DATE, '2026-10-16'::DATE, NULL, 'SI'::dictamen_academia_enum, 27, 'JUAN FLAVIO MOLAR OROZCO', '26-2-3', 'P.B146/2026', '2026-10-16'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(131, '22070748', 'Ago-Dic 2026', 'ESTRUCTURACION Y ACTUALIZACION DEL MANUAL TECNICO DE IDENTIFICACION DE DAÑOS A CONTENEDORES EN ALIANZA ESTRATEGICA PORTUARIA EN AREA DE PIV', 9, 'ALIANZA ESTRATEGICA PORTUARIA', 'ING. RODRIGO ALEJANDRO ROBLES JIMENEZ', 'DE 8:30 A 14:00 HORAS', '17 AGOSTO 2026 AL 01 MARZO 2027', '2026-10-10'::DATE, NULL, '2026-10-09'::DATE, 'P.A137/2026', '2026-10-15'::DATE, '2026-10-16'::DATE, NULL, 'SI'::dictamen_academia_enum, 6, 'JUAN CARLOS ESPINOZA VELASCO', '26-2-1', 'P.B147/2026', '2026-10-16'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(132, '22070747', 'Ago-Dic 2026', 'ANÁLISIS Y PROPUESTA DE MEJORA DEL SISTEMA DE RECLUTAMIENTO PARA PAROS DE PLANTA POR GRUPO INDUSTRIAL AGUILA', 5, 'AGUILA MANTENIMIENTO INDUSTRIAL, S.A. DE C.V.', 'C.P. VERÓNICA AZUARA SANTIAGO', 'DE 8:00 A 18:00 HRS', '8 DE SEPTIEMBRE DE 2026 AL 8 DE ENERO DE 2027', '2026-10-12'::DATE, NULL, '2026-10-12'::DATE, 'P.A138/2026', NULL, NULL, NULL, 'SI'::dictamen_academia_enum, 2, 'ALFONSO BARBOSA MORENO', '26-2-2', 'P.B148/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(133, '21071517', 'Ago-Dic 2026', 'ANALISIS Y PROPUESTA DE MEJORA DE UN SISTEMA INTEGRAL PARA GESTION Y CONTROL DE PROCESOS COMERCIALES EN UNA EMPRESA DE TRANSPORTE TERRESTRE DE CARGA', 69, 'MULTIENLACES LOGÍSTICOS TERRESTRES,S.A. DE C.V.', 'LIC. ITZEL ALVARADO MEDELLIN', 'DE 8:30 a 18:00 HORAS', '1 SEPTIEMBRE 2026 AL 4 DE ENERO 2027', '2026-10-12'::DATE, NULL, '2026-10-12'::DATE, 'P.A139/2026', '2026-10-15'::DATE, '2026-10-16'::DATE, NULL, 'SI'::dictamen_academia_enum, 23, 'GABRIELA MALIBRAN DOMINGUEZ', '26-2-1', 'P.B149/2026', '2026-10-16'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(134, '21071081', 'Ene-Jun 2026', 'ANALISIS Y PROPUESTA DE MEJORA DEL SISTEMA DE MANTENIMIENTO PREVENTIVO PARA MOLDES DE INYECCION', 60, 'INNOVAGAN ,S.A. DE C.V.', 'ING. ANTONIO ABAD RAMÍREZ RODRÍGUEZ', 'DE 9:00 A 18:00 HORAS', '2 JUNIO AL 6 DICIEMBRE DE 2026', '2026-10-12'::DATE, NULL, '2026-10-12'::DATE, 'P.A140/2026', '2026-10-15'::DATE, '2026-10-16'::DATE, NULL, 'SI'::dictamen_academia_enum, 8, 'JESUS ESQUIVEL RODRIGUEZ', '26-2-1', 'P.B150/2026', '2026-10-16'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(135, '22070902', 'Ago-Dic 2026', 'ANÁLISIS DE TIEMPOS PARA LA MEJORA DEL PROCESO DE MANTENIMIENTO DE VÁLVULAS INDUSTRIALES TIPO GLOBO EN LA EMPRESA CALIBRACIONES E INSTRUMENTACION PARA LA INDUSTRIA', 19, 'CALIBRACIONES E INSTRUMENTACION PARA LA INDUSTRIA', 'ING. HÉCTOR GALVÁN NAVA', 'DE 08:00 A 13:00 HORAS', '31 AGOSTO AL 21 ENERO 2027', '2026-10-12'::DATE, NULL, '2026-10-12'::DATE, 'P.A141/2026', NULL, NULL, NULL, 'SI'::dictamen_academia_enum, 3, 'BLANCA NELVA CASTILLO BOLAÑOS', '26-2-2', 'P.B151/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(136, '22071342', 'Ago-Dic 2026', 'ANALISIS Y PROPUESTA DE MEJORA DEL PROCESO DE EMPAQUE Y EMBARQUE PARA LA REDUCCION DE SCRAP MEDIANTE LA IMPLEMENTACION DE LA METODOLOGIA 9S', 56, 'INDELPRO,S.A. DE C.V.', 'ING. MAURICIO MAR SANCHEZ', 'DE 8:00 A 17:30 HRS', '17 AGOSTO 2026 AL 17 ENERO 2027', '2026-10-13'::DATE, NULL, NULL, 'P.A142/2026', '2026-10-15'::DATE, '2026-10-16'::DATE, NULL, 'Pendiente'::dictamen_academia_enum, 31, 'GUILLERMO CARLOS PEÑA GARCÍA', '26-2-2', 'P.B152/2026', '2026-10-16'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(137, '22070781', 'Ago-Dic 2026', 'DESARROLLO E IMPLEMENTACION DEL PROCESO DE INGENIERIA EN LA EMPRESA CONSULTORIA EN OBRA S.A. DE C.V.', 34, 'CONSULTORÍA EN OBRA, S.A. DE C.V.', 'ING. CARLOS ANTONIO JACOBO GARCÍA', 'DE 8:30 A 17:30 HORAS', '1 SEPTEIMBRE 2026 AL 30 ENERO 2027', '2026-10-13'::DATE, NULL, NULL, 'P.A143/2026', '2026-10-15'::DATE, '2026-10-16'::DATE, NULL, 'Pendiente'::dictamen_academia_enum, 20, 'VERÓNICA HERNÁNDEZ MORALES', '26-2-2', 'P.B153/2026', '2026-10-16'::DATE, 'Expediente Completo'::estado_expediente_enum, NULL),
(138, '22070867', 'Ago-Dic 2026', 'ANALISIS DE LAS DESVIACIONES ENTRE TIEMPOS PROGRAMADOS Y TIEMPOS REALES DE EJECUCION EN ACTIVIDADES DE MANTENIMIENTO ELECTRICO, MECANICO E INSTRUMENTACION MEDIANTE EL SEGUIMIENTO DE LAS ACTIVIDADES EN CAMPO', 75, 'QUANTUM ENERGIA', 'ING. ANDRES ALBERTO ALEGRIA ZAMUDIO', 'DE 08:00 A 16:00 HORAS', '23 SEPTIEMBRE 2026 AL 23 ENERO 2027', '2026-10-12'::DATE, NULL, NULL, 'P.A144/2026', NULL, NULL, NULL, 'ASIGNADO'::dictamen_academia_enum, 30, 'JANNYA PÉREZ PANCARDO', '26,2,1', 'P.B154/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(139, '22070843', 'Ago-Dic 2026', 'ANALISIS DE TIEMPOS Y PRODUCTIVIDAD PARA LA MEJORA DEL PROCESO DE ABASTECIMIENTO EN EL DEPARTAMENTO DE COMPRAS DEL CENTRO ESPAÑOL DE TAMPICO', 22, 'CENTRO ESPAÑOL DE TAMPICO A.C.', 'C.P. GERARDO RAMOS', 'DE 09:00 A 13:00 HORAS', '14 SEPTIEMBRE 2026 AL 14 MARZO 2027', '2026-10-12'::DATE, NULL, NULL, 'P.A145/2026', NULL, NULL, NULL, 'ASIGNADO'::dictamen_academia_enum, 36, 'PEDRO RODRÍGUEZ PITÓN', '26-2-2', 'P.B155/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(140, '22070885', 'Ago-Dic 2026', 'ANALISIS Y PROPUESTA DE MEJORA DEL PROCESO ADMINISTRATIVO PARA LA INTEGRACION Y GESTION DE POLIZAS', 62, 'INSTITUTO NACIONAL ELECTORAL', 'LIC. LIBRADO HERNANDEZ GONZALEZ', 'DE 09:00 A 14:00 HORAS', '08 SEPTIEMBRE 2026 AL 22 ENERO 2027', '2026-10-12'::DATE, NULL, NULL, 'P.A146/2026', NULL, NULL, NULL, 'ASIGNADO'::dictamen_academia_enum, 22, 'JOSÉ LUIS LUCIO SILVA', '26-2-2', 'P.B156/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(141, '21070864', 'Ago-Dic 2026', 'ESTANDARIZACION Y MEJORA DEL PROCESO DE GESTION Y SEGUIMIENTO DE RFIs EN PROYECTOS DE FABRICACION INDUSTRIAL', 4, 'AGUILA FABRICACION', 'ING. EMILIO GONZALEZ JUAREZ', 'DE 08:00 A 18:00 HORAS', '19 AGOSTO 2026 AL 19 AGOSTO 2027', '2026-10-12'::DATE, NULL, NULL, 'P.A147/2026', NULL, NULL, NULL, 'ASIGNADO'::dictamen_academia_enum, 6, 'JUAN CARLOS ESPINOSA VELASCO', '26-2-2', 'P.B157/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(142, '22070758', 'Ago-Dic 2026', 'IDENTIFICACION DE NECESIDADES DE ALTA DE SISTEMAS Y EQUIPOS EN SAP Y DTIs', 75, 'QUANTUM ENERGIA', 'ING. FRANCISCO JAVIER RODRIGUEZ BARRON', 'DE 08:00 A 16:00 HORAS', '31 AGOSTO 2026 AL 31 DICIEMBRE 2026', NULL, '12 OC 26', NULL, 'P.A148/2026', NULL, NULL, NULL, 'ASIGNADO'::dictamen_academia_enum, 9, 'MA. ELENA GARCÍA ALVARADO', '26-2-2', 'P.B158/2026', NULL, 'Expediente Completo'::estado_expediente_enum, NULL),
(143, '22071325', 'Ago-Dic 2026', 'ANÁLISIS Y PROPUESTA DEL PROCESO DE INSPECCIÓN DE EMBARQUES PARA ASEGURAR LA CONFORMIDAD DEL PRODUCTO TERMINADO', 96, 'VIBRANTS ERACHEM MEXICO,S.A. DE C.V.', 'ING. REYNALDO HERNANDEZ MOROS', 'DE 08:00 A 16:00 HORAS', '3 AGOSTO AL 3 DE DICIEMBRE 2026', '2026-10-12'::DATE, NULL, NULL, NULL, NULL, NULL, NULL, 'ASIGNADO'::dictamen_academia_enum, 1, 'ENEDINA ALVAREZ CRUZ', '26-2-3', NULL, NULL, 'En Trámite (Falta Oficio Asesor)'::estado_expediente_enum, NULL),
(144, '22070803', 'Ago-Dic 2026', 'ANÁLISIS Y PROPUESTA DE MEJORA DEL SISTEMA DE CONTROL DE ALMACÉN', 84, 'SERVICIOS TECNICOS PETROLEROS NACIONALES,S.A. DE C.V.', 'ING, MARISSA CORDERO DEL ÁNGEL', 'DE 08:00 A 16:00 HORAS', '2 SEPTIEMBRE 2026 AL  4 ENERO 2027', '2026-10-12'::DATE, NULL, NULL, NULL, NULL, NULL, NULL, 'ASIGNADO'::dictamen_academia_enum, 19, 'JOSÉ REFUGIO HERNÁNDEZ MENDOZA', '26-2-2', NULL, NULL, 'En Trámite (Falta Oficio Asesor)'::estado_expediente_enum, NULL),
(145, '21071139', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(146, '21071503', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(147, '21070867', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(148, '22070725', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(149, '22070753', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(150, '21071636', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(151, '21070923', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(152, '22070884', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(153, '22071193', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(154, '21071635', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(155, '22070852', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(156, '22070800', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(157, '21070904', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(158, '21071146', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(159, '21070956', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(160, '21071000', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(161, '21070917', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(162, '21071028', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(163, '21070907', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(164, '22070858', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(165, '21071029', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(166, '20071299', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(167, 'C20070520', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(168, '22070924', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(169, '22070743', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(170, '22070938', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(171, '22070929', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(172, '22070775', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(173, '21071523', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(174, '19070566', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(175, '21070947', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(176, '20071423', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(177, '21071075', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(178, '21071084', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(179, '20071278', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(180, '20071280', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(181, '21070875', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas'),
(182, '21070934', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(183, '22070863', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Inscrito en SII desde el 08 sep; no ha entregado hojas físicas'),
(184, '23070118', 'Ago-Dic 2026', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No entregado'::dictamen_academia_enum, NULL, NULL, NULL, NULL, NULL, 'Inscrito en SII sin Anteproyecto'::estado_expediente_enum, 'Dado de alta en SII después del 08 sep; no ha entregado hojas físicas');
SELECT setval('expedientes_residencias_id_expediente_seq', (SELECT MAX(id_expediente) FROM expedientes_residencias));
