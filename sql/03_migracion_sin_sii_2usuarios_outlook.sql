-- ============================================================================
-- MIGRACIÓN INTEGRAL: SIN SII, EXACTAMENTE 2 USUARIOS Y AVISOS POR OUTLOOK
-- Base de Datos: residencias_industrial_db (PostgreSQL 16)
-- ============================================================================

SET client_encoding = 'UTF8';

BEGIN;

-- 1. Agregar correo institucional del alumno y trazabilidad de avisos Outlook
ALTER TABLE alumnos
    ADD COLUMN IF NOT EXISTS correo_institucional VARCHAR(160);

UPDATE alumnos
SET correo_institucional = LOWER('l' || TRIM(numero_control) || '@cdmadero.tecnm.mx')
WHERE correo_institucional IS NULL OR TRIM(correo_institucional) = '';

ALTER TABLE expedientes_residencias
    ADD COLUMN IF NOT EXISTS correo_aviso_enviado VARCHAR(160),
    ADD COLUMN IF NOT EXISTS medio_notificacion VARCHAR(40);

-- 2. Eliminar expedientes originados únicamente por cruce SII (sin hojas impresas)
DELETE FROM expedientes_residencias
WHERE estado_expediente = 'Inscrito en SII sin Anteproyecto';

-- Limpiar alumnos que quedaron sin ningún expediente físico
DELETE FROM alumnos a
WHERE NOT EXISTS (
    SELECT 1 FROM expedientes_residencias e
    WHERE e.numero_control = a.numero_control
);

-- 3. Dejar exactamente 2 usuarios activos en usuarios_sistema (Usuario 1 Gestión y Usuario 2 Academia)
UPDATE usuarios_sistema
SET username = 'usuario1_gestion',
    nombre_mostrar = 'Usuario 1 · Gestión (Recepción, Oficios y Avisos)',
    responsabilidad = 'Recepción de hojas impresas, captura de solicitudes, control de pausados y S.S., emisión de Oficios P.A/P.B y avisos por Outlook',
    activo = TRUE
WHERE rol = 'GESTION_1';

UPDATE usuarios_sistema
SET activo = FALSE,
    nombre_mostrar = 'Coordinación de Gestión (Desactivado - Consolidado en Usuario 1)'
WHERE rol = 'GESTION_2';

UPDATE usuarios_sistema
SET username = 'usuario2_academia',
    nombre_mostrar = 'Usuario 2 · Academia (Asignación de Asesores)',
    responsabilidad = 'Dictamen técnico de anteproyectos, consulta de carga de los 42 docentes y asignación de Asesor Interno',
    activo = TRUE
WHERE rol = 'ACADEMIA';

-- 4. Actualizar vistas y función de búsqueda sin referencias a SII
DROP VIEW IF EXISTS v_auditoria_sii_y_excepciones;
DROP VIEW IF EXISTS v_excepciones_y_pausados;

CREATE VIEW v_excepciones_y_pausados AS
SELECT
    e.id_expediente,
    e.numero_control,
    a.nombre_completo AS alumno,
    a.correo_institucional,
    e.semestre,
    a.estado_servicio_social,
    e.estado_expediente,
    CASE
        WHEN e.estado_expediente = 'Detenido por Servicio Social' THEN 'DETENIDO: NO HA LIBERADO SERVICIO SOCIAL'
        WHEN e.estado_expediente = 'Pausado / Sin Oficio' THEN 'TRÁMITE PAUSADO / INCONCLUSO POR EL ALUMNO'
        WHEN a.estado_servicio_social <> 'Liberado' THEN 'ALERTA: SERVICIO SOCIAL POR VERIFICAR'
        ELSE 'CASO ESPECIAL / REASIGNACIÓN'
    END AS tipo_excepcion,
    e.titulo_anteproyecto,
    e.observaciones
FROM expedientes_residencias e
JOIN alumnos a ON e.numero_control = a.numero_control
WHERE e.estado_expediente IN ('Pausado / Sin Oficio', 'Detenido por Servicio Social', 'Caso Especial / Reasignación')
   OR a.estado_servicio_social <> 'Liberado'
ORDER BY e.estado_expediente, a.nombre_completo;

DROP VIEW IF EXISTS v_kpis_dashboard;
CREATE VIEW v_kpis_dashboard AS
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) FILTER (WHERE e.estado_expediente = 'Expediente Completo') AS expedientes_completos,
    COUNT(*) FILTER (WHERE e.estado_expediente IN ('En Revisión por Academia', 'Pendiente Asignar Asesor (Academia)', 'En Trámite (Falta Oficio Asesor)')) AS pendientes_academia_o_oficio,
    COUNT(*) FILTER (WHERE e.estado_expediente = 'Pausado / Sin Oficio') AS tramites_pausados,
    COUNT(*) FILTER (WHERE e.estado_expediente = 'Detenido por Servicio Social') AS detenidos_ss,
    COUNT(*) FILTER (WHERE a.estado_servicio_social <> 'Liberado') AS alertas_servicio_social,
    COUNT(*) FILTER (WHERE e.fecha_notificado_alumno IS NULL AND e.estado_expediente NOT IN ('Pausado / Sin Oficio', 'Detenido por Servicio Social')) AS pendientes_notificar
FROM expedientes_residencias e
JOIN alumnos a ON e.numero_control = a.numero_control;

DROP VIEW IF EXISTS v_expedientes_completos;
CREATE VIEW v_expedientes_completos AS
SELECT
    e.id_expediente,
    e.numero_control,
    a.nombre_completo AS alumno,
    a.correo_institucional,
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
    e.correo_aviso_enviado,
    e.medio_notificacion,
    e.fecha_envio_aut_correo,
    COALESCE(d.nombre_docente, e.nombre_asesor_interno_texto) AS asesor_interno,
    e.folio_control_academia,
    e.oficio_asignacion_asesor,
    e.fecha_envio_asesor_correo,
    e.asesor_externo,
    e.observaciones
FROM expedientes_residencias e
JOIN alumnos a ON e.numero_control = a.numero_control
LEFT JOIN empresas_receptoras emp ON e.id_empresa = emp.id_empresa
LEFT JOIN docentes_asesores d ON e.id_docente_asesor = d.id_docente
ORDER BY e.id_expediente;

DROP FUNCTION IF EXISTS fn_buscar_expedientes(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION fn_buscar_expedientes(
    p_texto_busqueda VARCHAR DEFAULT NULL,
    p_semestre VARCHAR DEFAULT NULL,
    p_estado VARCHAR DEFAULT NULL,
    p_servicio_social VARCHAR DEFAULT NULL,
    p_asesor_interno VARCHAR DEFAULT NULL
)
RETURNS TABLE(
    id_expediente INT,
    numero_control VARCHAR,
    nombre_alumno VARCHAR,
    correo_institucional VARCHAR,
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
    observaciones TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id_expediente,
        e.numero_control,
        a.nombre_completo AS nombre_alumno,
        a.correo_institucional,
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
                e.numero_control, a.nombre_completo, a.correo_institucional,
                e.titulo_anteproyecto, e.nombre_empresa_texto, e.nombre_asesor_interno_texto,
                e.asesor_externo, e.oficio_autorizacion, e.oficio_asignacion_asesor,
                e.folio_control_academia, e.observaciones
            ) ILIKE '%' || TRIM(p_texto_busqueda) || '%'
        )
    ORDER BY e.id_expediente ASC;
END;
$$;

COMMIT;
