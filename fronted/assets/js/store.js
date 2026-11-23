/**
 * ResidenciasStore: Capa de datos y reglas de negocio del Sistema de Residencias.
 * Modo principal: Conexión en vivo a PostgreSQL 16 vía Flask + Procedimientos Almacenados.
 * Respaldo automático: localStorage + window.INITIAL_* si el servidor API no está activo.
 */
(function (global) {
  'use strict';

  const KEYS = {
    RESIDENCIAS: 'tecnm.industrial.residencias.v3',
    MAESTROS: 'tecnm.industrial.maestros.v3',
    BITACORA: 'tecnm.industrial.bitacora.v3',
    ROLE: 'tecnm.industrial.role.v3'
  };

  const ROLE_META = {
    gestion1: {
      id: 'gestion1',
      userCode: 'GESTION_1',
      label: 'Usuario 1 · Gestión',
      shortLabel: 'Usuario 1',
      subtitle: 'Recepción de hojas, oficios P.A/P.B, pausados y avisos Outlook',
      isGestion: true,
      isAcademia: false,
      defaultView: 'expedientes'
    },
    academia: {
      id: 'academia',
      userCode: 'ACADEMIA',
      label: 'Usuario 2 · Academia',
      shortLabel: 'Usuario 2',
      subtitle: 'Dictamen técnico de anteproyectos y asignación de asesor interno',
      isGestion: false,
      isAcademia: true,
      defaultView: 'academia'
    }
  };

  let state = {
    residencias: [],
    maestros: [],
    bitacora: [],
    role: 'gestion1',
    apiMode: false,
    outlookStatus: {
      smtpConfigured: false,
      senderEmail: '',
      smtpHost: 'smtp.office365.com'
    },
    dbInfo: {
      connected: false,
      modeLabel: 'Modo Local (Offline)',
      dbUser: 'localStorage',
      dbName: 'Navegador'
    }
  };

  function normalizeText(str) {
    return String(str || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .trim();
  }

  function canonicalEspecialidad(esp) {
    const clean = String(esp || '').trim().toUpperCase();
    if (!clean || clean === 'INDUSTRIAL GENERAL') return 'INDUSTRIAL GENERAL';
    if (clean === 'LOGISTICA' || clean === 'LOGÍSTICA') return 'LOGÍSTICA';
    if (clean === 'POR DEFINIR') return 'POR DEFINIR';
    return clean;
  }

  function normalizeRecord(raw) {
    const r = { ...raw };
    r.control = String(r.control || '').trim();
    r.nombre = String(r.nombre || '').trim().toUpperCase();
    r.correoInstitucional = String(r.correoInstitucional || (r.control ? `l${r.control}@cdmadero.tecnm.mx` : '')).trim().toLowerCase();
    r.semestre = String(r.semestre || 'Ago-Dic 2026').trim();
    r.especialidad = canonicalEspecialidad(r.especialidad);
    r.proyecto = String(r.proyecto || '').trim();
    r.empresa = String(r.empresa || '').trim();
    r.horario = String(r.horario || '').trim();
    r.periodo = String(r.periodo || '').trim();
    r.asesorExterno = String(r.asesorExterno || '').trim();
    r.asesorInterno = String(r.asesorInterno || '').trim();
    r.folioAcademia = String(r.folioAcademia || '').trim();
    r.fechaEntregaFisica = String(r.fechaEntregaFisica || '').trim();
    r.fechaEntregaAcademia = String(r.fechaEntregaAcademia || '').trim();
    r.revisadoAcademia = String(r.revisadoAcademia || 'Pendiente').trim();
    r.oficioAutorizacion = String(r.oficioAutorizacion || '').trim();
    r.fechaImpresion = String(r.fechaImpresion || '').trim();
    r.notificadoAlumno = String(r.notificadoAlumno || '').trim();
    r.correoAvisoEnviado = String(r.correoAvisoEnviado || '').trim().toLowerCase();
    r.medioNotificacion = String(r.medioNotificacion || '').trim();
    r.fechaEnvioAutCorreo = String(r.fechaEnvioAutCorreo || '').trim();
    r.oficioAsesorInterno = String(r.oficioAsesorInterno || '').trim();
    r.fechaEnvioAsesorCorreo = String(r.fechaEnvioAsesorCorreo || '').trim();
    r.servicioSocial = String(r.servicioSocial || 'Por verificar').trim();
    r.estado = String(r.estado || 'En Revisión por Academia').trim();
    r.observaciones = String(r.observaciones || '').trim();
    return r;
  }

  function todayISO() {
    return new Date().toISOString().slice(0, 10);
  }

  function nowTimestamp() {
    return new Date().toISOString();
  }

  function persistLocal() {
    try {
      localStorage.setItem(KEYS.RESIDENCIAS, JSON.stringify(state.residencias));
      localStorage.setItem(KEYS.MAESTROS, JSON.stringify(state.maestros));
      localStorage.setItem(KEYS.BITACORA, JSON.stringify(state.bitacora));
      localStorage.setItem(KEYS.ROLE, state.role);
    } catch (err) {}
  }

  function buildInitialBitacora(records) {
    const sample = [];
    const notables = records.filter(
      (r) => r.estado !== 'Expediente Completo'
    ).slice(0, 8);
    notables.forEach((r, idx) => {
      sample.push({
        id: idx + 1,
        idExpediente: r.id,
        control: r.control,
        nombreAlumno: r.nombre,
        usuario: 'SISTEMA',
        operacion: 'CARGA_INICIAL',
        estadoAnterior: '—',
        estadoNuevo: r.estado,
        descripcion: r.observaciones || `Expediente cargado (${r.semestre})`,
        fecha: '2026-11-18T20:25:00.000Z'
      });
    });
    return sample;
  }

  function loadLocalFallback() {
    let loaded = false;
    try {
      const rawRes = localStorage.getItem(KEYS.RESIDENCIAS);
      const rawMae = localStorage.getItem(KEYS.MAESTROS);
      const rawBit = localStorage.getItem(KEYS.BITACORA);
      if (rawRes && rawMae) {
        state.residencias = JSON.parse(rawRes).map(normalizeRecord);
        state.maestros = JSON.parse(rawMae);
        state.bitacora = rawBit ? JSON.parse(rawBit) : buildInitialBitacora(state.residencias);
        loaded = true;
      }
    } catch (err) {
      loaded = false;
    }

    if (!loaded) {
      const initialRes = Array.isArray(global.INITIAL_RESIDENCIAS) ? global.INITIAL_RESIDENCIAS : [];
      const initialMae = Array.isArray(global.INITIAL_MAESTROS) ? global.INITIAL_MAESTROS : [];
      state.residencias = initialRes.map(normalizeRecord);
      state.maestros = JSON.parse(JSON.stringify(initialMae));
      state.bitacora = buildInitialBitacora(state.residencias);
      persistLocal();
    }
    state.apiMode = false;
    state.dbInfo = {
      connected: false,
      modeLabel: 'Modo Local (Offline)',
      dbUser: 'localStorage',
      dbName: 'Navegador'
    };
  }

  function applyServerData(payload) {
    if (!payload) return;
    state.residencias = (payload.residencias || []).map(normalizeRecord);
    state.maestros = payload.maestros || [];
    state.bitacora = payload.bitacora || [];
  }

  async function init() {
    try {
      const savedRole = localStorage.getItem(KEYS.ROLE);
      if (ROLE_META[savedRole]) state.role = savedRole;
      else state.role = 'gestion1';
    } catch (err) {}

    if (global.location && global.location.protocol !== 'file:') {
      try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 2200);
        const healthRes = await fetch('/api/health', { cache: 'no-store', signal: controller.signal });
        clearTimeout(timer);

        if (healthRes.ok) {
          const health = await healthRes.json();
          if (health && health.ok) {
            const [bootRes, outlookRes] = await Promise.all([
              fetch('/api/bootstrap', { cache: 'no-store' }),
              fetch('/api/outlook/status', { cache: 'no-store' }).catch(() => null)
            ]);
            if (outlookRes && outlookRes.ok) {
              const oJson = await outlookRes.json().catch(() => null);
              if (oJson && oJson.ok) {
                state.outlookStatus = {
                  smtpConfigured: Boolean(oJson.smtpConfigured),
                  senderEmail: oJson.senderEmail || '',
                  smtpHost: oJson.smtpHost || 'smtp.office365.com'
                };
              }
            }
            if (bootRes.ok) {
              const boot = await bootRes.json();
              if (boot && boot.ok && boot.data) {
                applyServerData(boot.data);
                state.apiMode = true;
                state.dbInfo = {
                  connected: true,
                  modeLabel: 'PostgreSQL 16 · SP Seguro',
                  dbUser: health.dbUser || 'app_residencias_user',
                  dbName: health.dbName || 'residencias_industrial_db'
                };
                return;
              }
            }
          }
        }
      } catch (err) {
        // Fallback automático a modo local si no está levantado backend/server.py
      }
    }

    loadLocalFallback();
  }

  async function syncFromServer() {
    if (!state.apiMode) {
      resetLocal();
      return false;
    }
    const bootRes = await fetch('/api/bootstrap', { cache: 'no-store' });
    const boot = await bootRes.json();
    if (!bootRes.ok || !boot.ok) {
      throw new Error((boot && boot.error) || 'No se pudo sincronizar con PostgreSQL.');
    }
    applyServerData(boot.data);
    return true;
  }

  function resetLocal() {
    try {
      localStorage.removeItem(KEYS.RESIDENCIAS);
      localStorage.removeItem(KEYS.MAESTROS);
      localStorage.removeItem(KEYS.BITACORA);
    } catch (err) {}
    loadLocalFallback();
  }

  async function apiPost(url, bodyObj) {
    const roleMeta = getRoleMeta();
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-System-Role': roleMeta.userCode
      },
      body: JSON.stringify(bodyObj || {})
    });
    const json = await res.json().catch(() => ({ ok: false, error: 'Respuesta inválida del servidor' }));
    if (!res.ok || !json.ok) {
      throw new Error(json.error || `Error HTTP ${res.status}`);
    }
    if (json.data) {
      applyServerData(json.data);
    }
    return json;
  }

  function addBitacoraLocal(entry) {
    const nextId = state.bitacora.reduce((m, b) => Math.max(m, b.id || 0), 0) + 1;
    const roleInfo = getRoleMeta();
    state.bitacora.unshift({
      id: nextId,
      idExpediente: entry.idExpediente,
      control: entry.control,
      nombreAlumno: entry.nombreAlumno,
      usuario: roleInfo.userCode,
      operacion: entry.operacion,
      estadoAnterior: entry.estadoAnterior || '—',
      estadoNuevo: entry.estadoNuevo || '—',
      descripcion: entry.descripcion,
      fecha: nowTimestamp()
    });
    if (state.bitacora.length > 300) {
      state.bitacora = state.bitacora.slice(0, 300);
    }
  }

  function getConnectionInfo() {
    return state.dbInfo;
  }

  function getRole() {
    return state.role;
  }

  function getRoleMeta(roleId) {
    return ROLE_META[roleId || state.role] || ROLE_META.gestion1;
  }

  function setRole(roleId) {
    if (!ROLE_META[roleId]) return getRoleMeta();
    state.role = roleId;
    try {
      localStorage.setItem(KEYS.ROLE, state.role);
    } catch (err) {}
    return getRoleMeta();
  }

  function getResidencias() {
    return state.residencias;
  }

  function getById(id) {
    return state.residencias.find((r) => Number(r.id) === Number(id)) || null;
  }

  function findByControl(control) {
    const clean = String(control || '').trim();
    if (!clean) return null;
    return state.residencias.find((r) => r.control === clean) || null;
  }

  function getMaestros() {
    return state.maestros;
  }

  function getBitacora() {
    return state.bitacora;
  }

  function teacherTokens(name) {
    return normalizeText(name)
      .replace(/\b(ing|lic|dr|dra|mc|ma|mai|mia|cp|mtre|sia|teniente|corbeta)\b\.?/g, ' ')
      .split(/[^a-z]+/)
      .filter((t) => t.length > 2);
  }

  function doesAdvisorMatchTeacher(asesorStr, teacherName) {
    const ai = normalizeText(asesorStr);
    if (!ai) return false;
    const tokens = teacherTokens(teacherName);
    if (tokens.length === 0) return false;
    const matches = tokens.filter((t) => ai.includes(t)).length;
    return matches >= Math.min(2, tokens.length);
  }

  function countActiveForTeacher(teacherName) {
    return state.residencias.filter((r) => doesAdvisorMatchTeacher(r.asesorInterno, teacherName)).length;
  }

  function getResidentsForTeacher(teacherName) {
    return state.residencias.filter((r) => doesAdvisorMatchTeacher(r.asesorInterno, teacherName));
  }

  function getNextFolio(tipo, anio = 2026) {
    const isPA = String(tipo).toUpperCase() === 'PA';
    const prefix = isPA ? 'P.A' : 'P.B';
    const regex = new RegExp(`^P\\.${isPA ? 'A' : 'B'}(\\d+)\\/${anio}$`, 'i');
    let maxNum = 0;
    state.residencias.forEach((r) => {
      const val = isPA ? r.oficioAutorizacion : r.oficioAsesorInterno;
      const match = String(val || '').trim().match(regex);
      if (match) {
        const n = parseInt(match[1], 10);
        if (n > maxNum) maxNum = n;
      }
    });
    return `${prefix}${String(maxNum + 1).padStart(3, '0')}/${anio}`;
  }

  function getNextAcademiaCode(asesorName) {
    if (!asesorName) return '26-1-1';
    const residents = getResidentsForTeacher(asesorName);
    let maxLot = 0;
    residents.forEach((r) => {
      const m = String(r.folioAcademia || '').match(/26-1-(\d+)/);
      if (m) {
        const n = parseInt(m[1], 10);
        if (n > maxLot) maxLot = n;
      }
    });
    return `26-1-${maxLot + 1}`;
  }

  function getUniqueSemestres() {
    const order = ['Ago-Dic 2026', 'Ene-Jun 2026', 'Ago-Dic 2025', 'Ene-Jun 2025', 'Sin especificar'];
    const set = new Set(state.residencias.map((r) => r.semestre).filter(Boolean));
    return Array.from(set).sort((a, b) => {
      const ia = order.indexOf(a);
      const ib = order.indexOf(b);
      if (ia !== -1 && ib !== -1) return ia - ib;
      if (ia !== -1) return -1;
      if (ib !== -1) return 1;
      return a.localeCompare(b);
    });
  }

  function getUniqueEspecialidades() {
    const set = new Set(state.residencias.map((r) => r.especialidad).filter(Boolean));
    return Array.from(set).sort();
  }

  function getUniqueEmpresas() {
    const set = new Set(state.residencias.map((r) => r.empresa).filter(Boolean));
    return Array.from(set).sort((a, b) => a.localeCompare(b, 'es'));
  }

  function getUniqueAsesores() {
    const map = new Map();
    state.maestros.forEach((m) => {
      const upper = m.nombre.toUpperCase();
      map.set(normalizeText(upper), upper);
    });
    state.residencias.forEach((r) => {
      if (r.asesorInterno) {
        const upper = r.asesorInterno.toUpperCase();
        const key = normalizeText(upper);
        if (!map.has(key)) map.set(key, upper);
      }
    });
    return Array.from(map.values()).sort((a, b) => a.localeCompare(b, 'es'));
  }

  function isPendingAcademia(r) {
    if (!r.proyecto) return false;
    if (r.estado === 'Pausado / Sin Oficio' || r.estado === 'Detenido por Servicio Social') return false;
    return (
      r.estado === 'En Revisión por Academia' ||
      r.estado === 'Pendiente Asignar Asesor (Academia)' ||
      r.estado === 'En Trámite (Falta Oficio Asesor)' ||
      !r.asesorInterno ||
      !r.oficioAsesorInterno
    );
  }

  function isPendingGestionOficio(r) {
    if (!r.proyecto) return false;
    if (r.estado === 'Pausado / Sin Oficio' || r.estado === 'Detenido por Servicio Social') return false;
    return !r.oficioAutorizacion || !r.oficioAsesorInterno || !r.notificadoAlumno;
  }

  function getKPIs() {
    const total = state.residencias.length;
    const completos = state.residencias.filter((r) => r.estado === 'Expediente Completo').length;
    const pendientesAcademia = state.residencias.filter(isPendingAcademia).length;
    const sinAsesor = state.residencias.filter(
      (r) => r.proyecto && !r.asesorInterno && r.estado !== 'Pausado / Sin Oficio' && r.estado !== 'Detenido por Servicio Social'
    ).length;
    const pendientesGestionOficio = state.residencias.filter(
      (r) => r.proyecto && (!r.oficioAutorizacion || !r.oficioAsesorInterno) && r.estado !== 'Pausado / Sin Oficio' && r.estado !== 'Detenido por Servicio Social'
    ).length;
    const pendientesNotificar = state.residencias.filter(
      (r) => r.proyecto && !r.notificadoAlumno && r.estado !== 'Pausado / Sin Oficio' && r.estado !== 'Detenido por Servicio Social'
    ).length;
    const pausados = state.residencias.filter((r) => r.estado === 'Pausado / Sin Oficio').length;
    const detenidosSS = state.residencias.filter((r) => r.estado === 'Detenido por Servicio Social').length;
    const reasignaciones = state.residencias.filter((r) => r.estado === 'Caso Especial / Reasignación').length;
    const alertasSS = state.residencias.filter((r) => r.servicioSocial !== 'Liberado').length;

    return {
      total,
      completos,
      pendientesAcademia,
      sinAsesor,
      pendientesGestionOficio,
      pendientesNotificar,
      pausados,
      detenidosSS,
      reasignaciones,
      alertasSS
    };
  }

  function queryExpedientes(filters = {}) {
    const q = normalizeText(filters.q || '');
    const semestre = filters.semestre || 'ALL';
    const estado = filters.estado || 'ALL';
    const servicioSocial = filters.servicioSocial || 'ALL';
    const especialidad = filters.especialidad || 'ALL';
    const asesor = filters.asesor || 'ALL';
    const empresa = filters.empresa || 'ALL';
    const oficioFilter = filters.oficioFilter || 'ALL';
    const sortBy = filters.sortBy || 'id';
    const sortDir = filters.sortDir === 'desc' ? -1 : 1;

    const filtered = state.residencias.filter((r) => {
      if (semestre !== 'ALL' && r.semestre !== semestre) return false;

      if (estado === 'PENDIENTE_ACADEMIA') {
        if (!isPendingAcademia(r)) return false;
      } else if (estado === 'PENDIENTE_OFICIO') {
        if (!r.proyecto || (r.oficioAutorizacion && r.oficioAsesorInterno)) return false;
      } else if (estado !== 'ALL' && r.estado !== estado) {
        return false;
      }

      if (servicioSocial === 'SIN_SS') {
        if (r.servicioSocial === 'Liberado') return false;
      } else if (servicioSocial !== 'ALL' && r.servicioSocial !== servicioSocial) {
        return false;
      }

      if (especialidad !== 'ALL' && r.especialidad !== especialidad) return false;

      if (asesor === 'SIN_ASESOR') {
        if (r.asesorInterno) return false;
      } else if (asesor !== 'ALL') {
        if (!doesAdvisorMatchTeacher(r.asesorInterno, asesor) && normalizeText(r.asesorInterno) !== normalizeText(asesor)) {
          return false;
        }
      }

      if (empresa !== 'ALL' && normalizeText(r.empresa) !== normalizeText(empresa)) return false;

      if (oficioFilter === 'SIN_PA' && (!r.proyecto || r.oficioAutorizacion)) return false;
      if (oficioFilter === 'SIN_PB' && (!r.proyecto || r.oficioAsesorInterno)) return false;
      if (oficioFilter === 'COMPLETOS' && (!r.oficioAutorizacion || !r.oficioAsesorInterno)) return false;

      if (q) {
        const haystack = normalizeText([
          r.id, r.control, r.nombre, r.correoInstitucional, r.proyecto, r.empresa,
          r.especialidad, r.asesorInterno, r.asesorExterno,
          r.oficioAutorizacion, r.oficioAsesorInterno, r.folioAcademia,
          r.periodo, r.estado, r.observaciones
        ].join(' '));
        const terms = q.split(/\s+/).filter(Boolean);
        if (!terms.every((t) => haystack.includes(t))) return false;
      }

      return true;
    });

    filtered.sort((a, b) => {
      if (sortBy === 'nombre') return a.nombre.localeCompare(b.nombre, 'es') * sortDir;
      if (sortBy === 'control') return a.control.localeCompare(b.control) * sortDir;
      if (sortBy === 'fechaEntregaFisica') {
        return (a.fechaEntregaFisica || '0000').localeCompare(b.fechaEntregaFisica || '0000') * sortDir;
      }
      if (sortBy === 'estado') return a.estado.localeCompare(b.estado, 'es') * sortDir;
      return (Number(a.id) - Number(b.id)) * sortDir;
    });

    return filtered;
  }

  // =========================================================================
  // OPERACIONES DE ESCRITURA (POSTGRESQL SP VIA API O FALLBACK LOCAL)
  // =========================================================================

  async function registrarOSalvarExpediente(payload) {
    if (state.apiMode) {
      const json = await apiPost('/api/expedientes', payload);
      return getById(json.id) || findByControl(payload.control);
    }

    const clean = normalizeRecord(payload);
    if (!clean.control || !clean.nombre) {
      throw new Error('El número de control y el nombre del alumno son obligatorios.');
    }

    if (clean.servicioSocial === 'No Liberado (Irregular)') {
      clean.estado = 'Detenido por Servicio Social';
    }

    if (
      clean.proyecto &&
      clean.oficioAutorizacion &&
      clean.asesorInterno &&
      clean.oficioAsesorInterno &&
      clean.servicioSocial !== 'No Liberado (Irregular)' &&
      clean.estado !== 'Pausado / Sin Oficio' &&
      clean.estado !== 'Caso Especial / Reasignación'
    ) {
      clean.estado = 'Expediente Completo';
    }

    const existing = payload.id ? getById(payload.id) : findByControl(clean.control);
    if (existing) {
      const prevState = existing.estado;
      const idx = state.residencias.findIndex((r) => Number(r.id) === Number(existing.id));
      const updated = {
        ...existing,
        ...clean,
        id: existing.id
      };
      state.residencias[idx] = updated;
      addBitacoraLocal({
        idExpediente: updated.id,
        control: updated.control,
        nombreAlumno: updated.nombre,
        operacion: 'ACTUALIZACION_EXPEDIENTE',
        estadoAnterior: prevState,
        estadoNuevo: updated.estado,
        descripcion: `Expediente actualizado. Oficio P.A: ${updated.oficioAutorizacion || '—'} · Asesor: ${updated.asesorInterno || '—'} · S.S.: ${updated.servicioSocial}`
      });
      persistLocal();
      return updated;
    }

    const nextId = state.residencias.reduce((m, r) => Math.max(m, Number(r.id) || 0), 0) + 1;
    const created = { ...clean, id: nextId };
    state.residencias.unshift(created);
    addBitacoraLocal({
      idExpediente: created.id,
      control: created.control,
      nombreAlumno: created.nombre,
      operacion: 'ALTA_SOLICITUD_FISICA',
      estadoAnterior: 'Nuevo',
      estadoNuevo: created.estado,
      descripcion: `Recepción física de anteproyecto: "${created.proyecto.slice(0, 70)}..."`
    });
    persistLocal();
    return created;
  }

  async function gestionAceptarProyecto(id, opts = {}) {
    if (state.apiMode) {
      await apiPost(`/api/expedientes/${id}/aceptar-pa`, opts);
      return getById(id);
    }

    const rec = getById(id);
    if (!rec) return null;
    const prev = rec.estado;
    const folioPA = (opts.oficioAutorizacion || '').trim().toUpperCase() || rec.oficioAutorizacion || getNextFolio('PA', 2026);
    rec.oficioAutorizacion = folioPA;
    rec.fechaImpresion = opts.fechaImpresion || rec.fechaImpresion || todayISO();
    rec.fechaEntregaAcademia = opts.fechaEntregaAcademia || rec.fechaEntregaAcademia || todayISO();
    if (rec.revisadoAcademia === 'No entregado' || rec.revisadoAcademia === 'Pendiente') {
      rec.revisadoAcademia = 'Si';
    }
    if (rec.servicioSocial === 'No Liberado (Irregular)') {
      rec.estado = 'Detenido por Servicio Social';
    } else if (rec.asesorInterno && rec.oficioAsesorInterno) {
      rec.estado = 'Expediente Completo';
    } else if (rec.asesorInterno) {
      rec.estado = 'En Trámite (Falta Oficio Asesor)';
    } else {
      rec.estado = 'Pendiente Asignar Asesor (Academia)';
    }
    addBitacoraLocal({
      idExpediente: rec.id,
      control: rec.control,
      nombreAlumno: rec.nombre,
      operacion: 'EMISION_OFICIO_PA',
      estadoAnterior: prev,
      estadoNuevo: rec.estado,
      descripcion: `Gestión aceptó proyecto y emitió Oficio de Autorización ${folioPA}`
    });
    persistLocal();
    return rec;
  }

  async function gestionEmitirOficioAsesor(id, opts = {}) {
    if (state.apiMode) {
      await apiPost(`/api/expedientes/${id}/emitir-pb`, opts);
      return getById(id);
    }

    const rec = getById(id);
    if (!rec) return null;
    const prev = rec.estado;
    const folioPB = (opts.oficioAsesorInterno || '').trim().toUpperCase() || rec.oficioAsesorInterno || getNextFolio('PB', 2026);
    rec.oficioAsesorInterno = folioPB;
    rec.fechaEnvioAsesorCorreo = opts.fechaEnvioAsesorCorreo || rec.fechaEnvioAsesorCorreo || todayISO();
    if (!rec.oficioAutorizacion) {
      rec.oficioAutorizacion = getNextFolio('PA', 2026);
      rec.fechaImpresion = rec.fechaImpresion || todayISO();
    }
    if (rec.servicioSocial !== 'No Liberado (Irregular)') {
      rec.estado = rec.asesorInterno ? 'Expediente Completo' : 'Pendiente Asignar Asesor (Academia)';
    }
    addBitacoraLocal({
      idExpediente: rec.id,
      control: rec.control,
      nombreAlumno: rec.nombre,
      operacion: 'EMISION_OFICIO_PB',
      estadoAnterior: prev,
      estadoNuevo: rec.estado,
      descripcion: `Gestión emitió Oficio de Asignación de Asesor ${folioPB}`
    });
    persistLocal();
    return rec;
  }

  async function gestionNotificarAlumno(id) {
    return gestionEnviarAvisoOutlook(id, { modo: 'manual' });
  }

  async function gestionEnviarAvisoOutlook(id, opts = {}) {
    const recCurrent = getById(id);
    const correo = String(opts.correoDestino || (recCurrent ? recCurrent.correoInstitucional : '') || '').trim().toLowerCase();
    const asunto = String(opts.asunto || 'Aviso de Residencias Profesionales — Oficios listos').trim();
    const mensaje = String(opts.mensaje || '').trim();
    const modo = String(opts.modo || 'outlook_web').toLowerCase();

    if (state.apiMode) {
      const json = await apiPost(`/api/expedientes/${id}/notificar-outlook`, {
        correoDestino: correo,
        asunto,
        mensaje,
        modo
      });
      return {
        record: getById(id),
        sentViaSmtp: Boolean(json.sentViaSmtp),
        needsConfig: Boolean(json.needsConfig),
        registered: Boolean(json.registered),
        outlookWebUrl: json.outlookWebUrl || '',
        mailtoUrl: json.mailtoUrl || '',
        message: json.message || ''
      };
    }

    const rec = getById(id);
    if (!rec) return null;
    if (correo) rec.correoInstitucional = correo;
    rec.notificadoAlumno = todayISO();
    rec.correoAvisoEnviado = correo;
    rec.medioNotificacion = modo === 'manual' ? 'Aviso Manual' : 'Outlook Web';
    addBitacoraLocal({
      idExpediente: rec.id,
      control: rec.control,
      nombreAlumno: rec.nombre,
      operacion: 'NOTIFICACION_OUTLOOK',
      estadoAnterior: rec.estado,
      estadoNuevo: rec.estado,
      descripcion: `Aviso de recolección vía ${rec.medioNotificacion} a ${correo || 'ventanilla'} (${rec.notificadoAlumno})`
    });
    persistLocal();

    const params = new URLSearchParams({ to: correo, subject: asunto, body: mensaje });
    return {
      record: rec,
      sentViaSmtp: false,
      needsConfig: modo === 'smtp',
      registered: true,
      outlookWebUrl: `https://outlook.office.com/mail/deeplink/compose?${params.toString()}`,
      mailtoUrl: `mailto:${correo}?${new URLSearchParams({ subject: asunto, body: mensaje }).toString()}`,
      message: ''
    };
  }

  function getOutlookStatus() {
    return state.outlookStatus;
  }

  async function academiaAsignarAsesor(id, opts = {}) {
    if (state.apiMode) {
      await apiPost(`/api/expedientes/${id}/asignar-asesor`, opts);
      return getById(id);
    }

    const rec = getById(id);
    if (!rec) return null;
    const prev = rec.estado;
    const asesor = String(opts.asesorInterno || '').trim().toUpperCase();
    if (!asesor) {
      throw new Error('Debes seleccionar un docente como Asesor Interno.');
    }

    rec.asesorInterno = asesor;
    rec.folioAcademia = (opts.folioAcademia || '').trim() || rec.folioAcademia || getNextAcademiaCode(asesor);
    rec.revisadoAcademia = opts.dictamen || 'ASIGNADO';
    if (opts.autoOficioPB && !rec.oficioAsesorInterno) {
      rec.oficioAsesorInterno = getNextFolio('PB', 2026);
      rec.fechaEnvioAsesorCorreo = rec.fechaEnvioAsesorCorreo || todayISO();
    }
    if (rec.servicioSocial === 'No Liberado (Irregular)') {
      rec.estado = 'Detenido por Servicio Social';
    } else if (rec.oficioAutorizacion && rec.oficioAsesorInterno) {
      rec.estado = 'Expediente Completo';
    } else {
      rec.estado = 'En Trámite (Falta Oficio Asesor)';
    }
    addBitacoraLocal({
      idExpediente: rec.id,
      control: rec.control,
      nombreAlumno: rec.nombre,
      operacion: 'ASIGNACION_ASESOR_ACADEMIA',
      estadoAnterior: prev,
      estadoNuevo: rec.estado,
      descripcion: `Academia asignó a ${asesor} (Folio ${rec.folioAcademia})`
    });
    persistLocal();
    return rec;
  }

  async function cambiarExcepcion(id, opts = {}) {
    if (state.apiMode) {
      await apiPost(`/api/expedientes/${id}/excepcion`, opts);
      return getById(id);
    }

    const rec = getById(id);
    if (!rec) return null;
    const prev = rec.estado;
    const prevSS = rec.servicioSocial;
    if (opts.servicioSocial) rec.servicioSocial = opts.servicioSocial;
    if (opts.estado) {
      rec.estado = opts.estado;
    } else if (rec.servicioSocial === 'No Liberado (Irregular)') {
      rec.estado = 'Detenido por Servicio Social';
    } else if (prev === 'Detenido por Servicio Social' && rec.servicioSocial === 'Liberado') {
      rec.estado = rec.asesorInterno && rec.oficioAsesorInterno
        ? 'Expediente Completo'
        : 'En Revisión por Academia';
    }
    if (opts.observaciones !== undefined) {
      rec.observaciones = String(opts.observaciones).trim();
    }
    addBitacoraLocal({
      idExpediente: rec.id,
      control: rec.control,
      nombreAlumno: rec.nombre,
      operacion: 'CAMBIO_EXCEPCION_O_SS',
      estadoAnterior: `${prev} (${prevSS})`,
      estadoNuevo: `${rec.estado} (${rec.servicioSocial})`,
      descripcion: rec.observaciones || `Actualización a ${rec.servicioSocial}`
    });
    persistLocal();
    return rec;
  }

  function exportToCSV(rows, filenamePrefix = 'consulta_residencias_industrial') {
    const headers = [
      'ID', 'CONTROL', 'ALUMNO', 'CORREO_INSTITUCIONAL', 'SEMESTRE', 'ESPECIALIDAD',
      'SERVICIO_SOCIAL', 'ESTADO_EXPEDIENTE', 'ANTEPROYECTO', 'EMPRESA',
      'HORARIO', 'PERIODO', 'FECHA_ENTREGA_FISICA', 'FECHA_ENTREGA_ACADEMIA',
      'REVISADO_ACADEMIA', 'OFICIO_AUTORIZACION', 'FECHA_IMPRESION',
      'NOTIFICADO_ALUMNO', 'CORREO_AVISO_ENVIADO', 'MEDIO_NOTIFICACION',
      'ASESOR_INTERNO', 'FOLIO_ACADEMIA',
      'OFICIO_ASESOR_INTERNO', 'FECHA_ENVIO_ASESOR_CORREO',
      'ASESOR_EXTERNO', 'OBSERVACIONES'
    ];
    const esc = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const body = rows.map((r) => [
      r.id, r.control, r.nombre, r.correoInstitucional, r.semestre, r.especialidad,
      r.servicioSocial, r.estado, r.proyecto, r.empresa,
      r.horario, r.periodo, r.fechaEntregaFisica, r.fechaEntregaAcademia,
      r.revisadoAcademia, r.oficioAutorizacion, r.fechaImpresion,
      r.notificadoAlumno, r.correoAvisoEnviado, r.medioNotificacion,
      r.asesorInterno, r.folioAcademia,
      r.oficioAsesorInterno, r.fechaEnvioAsesorCorreo,
      r.asesorExterno, r.observaciones
    ].map(esc).join(','));

    const csv = '\uFEFF' + [headers.join(','), ...body].join('\r\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${filenamePrefix}_${todayISO()}.csv`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  global.ResidenciasStore = {
    init,
    reset: resetLocal,
    syncFromServer,
    getConnectionInfo,
    normalizeText,
    getRole,
    getRoleMeta,
    setRole,
    getResidencias,
    getById,
    findByControl,
    getMaestros,
    getBitacora,
    getUniqueSemestres,
    getUniqueEspecialidades,
    getUniqueEmpresas,
    getUniqueAsesores,
    countActiveForTeacher,
    getResidentsForTeacher,
    getNextFolio,
    getNextAcademiaCode,
    getKPIs,
    isPendingAcademia,
    isPendingGestionOficio,
    queryExpedientes,
    registrarOSalvarExpediente,
    gestionAceptarProyecto,
    gestionEmitirOficioAsesor,
    gestionNotificarAlumno,
    gestionEnviarAvisoOutlook,
    getOutlookStatus,
    academiaAsignarAsesor,
    cambiarExcepcion,
    exportToCSV,
    todayISO
  };
})(window);
