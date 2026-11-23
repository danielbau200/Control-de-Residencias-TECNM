/**
 * ResidenciasUI: Componentes y formateo tipográfico estilo macOS
 */
(function (global) {
  'use strict';

  const MONTHS_ES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  const LOWERCASE_WORDS = new Set(['de', 'del', 'la', 'las', 'los', 'y', 'e', 'en', 'el', 'al', 'a', 'para', 'con', 'por', 'o', 'u']);

  const ACADEMIC_PREFIXES = {
    'ing': 'Ing.',
    'ing.': 'Ing.',
    'lic': 'Lic.',
    'lic.': 'Lic.',
    'dr': 'Dr.',
    'dr.': 'Dr.',
    'dra': 'Dra.',
    'dra.': 'Dra.',
    'm.a': 'M.A.',
    'm.a.': 'M.A.',
    'ma': 'M.A.',
    'm.c': 'M.C.',
    'm.c.': 'M.C.',
    'mc': 'M.C.',
    'm.a.i': 'M.A.I.',
    'm.a.i.': 'M.A.I.',
    'mai': 'M.A.I.',
    'm.i.a': 'M.I.A.',
    'm.i.a.': 'M.I.A.',
    'mia': 'M.I.A.',
    'c.p': 'C.P.',
    'c.p.': 'C.P.',
    'cp': 'C.P.',
    '1er': '1er.',
    '1er.': '1er.',
    'mtre': 'Mtre.',
    'mtre.': 'Mtre.'
  };

  const ACRONYMS = new Set([
    'CFE', 'ISO', 'NOM', 'HVAC', 'SAP', 'ABC', 'SGA', 'SEMAR',
    'ABL', 'INE', 'CPG', 'STPS', 'DTI', 'DTIs', 'RFI', 'RFIs',
    'S.A.', 'C.V.', 'S.C.', 'A.C.', 'S.A.S.', 'S.A.S', 'S.R.L.', 'S.A', 'C.V', 'S.C', 'A.C',
    'PEMEX', 'IMSS', 'ISSSTE', 'TECNM', 'CNC', 'TPM', 'SMED', 'KPI', 'KPIs', 'ERP', 'MRP',
    'ASTIMAR', 'ASTIMAR-2', 'CENREPMAD-1', 'SECATMX', 'US', 'II', 'I.I', '9S', '5S'
  ]);

  function escapeHtml(str) {
    return String(str ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /**
   * Convierte nombres de MAYÚSCULAS ("SANTISBÓN CAMPA ANDREA", "M.A. ENEDINA ALVAREZ CRUZ")
   * a Title Case limpio y natural estilo macOS.
   */
  function formatPersonName(str) {
    const raw = String(str || '').trim();
    if (!raw) return '';
    return raw.split(/\s+/).map((token, idx) => {
      const lower = token.toLowerCase();
      if (ACADEMIC_PREFIXES[lower]) return ACADEMIC_PREFIXES[lower];
      if (idx > 0 && LOWERCASE_WORDS.has(lower)) return lower;
      // Manejar prefijos pegados como DR.ALFONSO
      if (lower.startsWith('dr.') && lower.length > 3) {
        const rest = lower.slice(3);
        return 'Dr. ' + rest.charAt(0).toUpperCase() + rest.slice(1);
      }
      if (lower === 'ma.' || lower === 'ma') return 'Ma.';
      return lower.charAt(0).toUpperCase() + lower.slice(1);
    }).join(' ');
  }

  /**
   * Convierte títulos de proyectos o empresas en ALL CAPS a Sentence Case legible,
   * preservando siglas técnicas e institucionales.
   */
  function formatTitleText(str) {
    const raw = String(str || '').trim();
    if (!raw) return '';
    const words = raw.split(/\s+/);
    return words.map((word, idx) => {
      const stripped = word.replace(/^[(["'«]+|[)\].,;:"'»]+$/g, '');
      const upperStripped = stripped.toUpperCase();

      // Preservar siglas exactas o códigos con números/guiones (ej. NOM-018-STPS-2015, ISO, CFE)
      if (ACRONYMS.has(upperStripped) || /^[A-Z0-9]+-[A-Z0-9-]+$/.test(upperStripped) || /^\d+[A-Z]+$/.test(upperStripped)) {
        return word.toUpperCase();
      }
      if (upperStripped === 'SA' || upperStripped === 'S.A.') return word.replace(stripped, 'S.A.');
      if (upperStripped === 'CV' || upperStripped === 'C.V.') return word.replace(stripped, 'C.V.');

      const lower = word.toLowerCase();
      if (idx === 0) {
        // Capitalizar primera letra alfabética (por si inicia con comillas o paréntesis)
        return lower.replace(/[a-záéíóúüñ]/i, (ch) => ch.toUpperCase());
      }
      return lower;
    }).join(' ');
  }

  function formatDateShort(iso) {
    const val = String(iso || '').trim();
    if (!val) return '—';
    const m = val.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!m) return escapeHtml(val);
    const monthIdx = parseInt(m[2], 10) - 1;
    const monthName = MONTHS_ES[monthIdx] || m[2];
    return `${m[3]} ${monthName} ${m[1]}`;
  }

  function formatDateTimeShort(iso) {
    if (!iso) return '—';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return escapeHtml(iso);
    const day = String(d.getDate()).padStart(2, '0');
    const mon = MONTHS_ES[d.getMonth()] || '';
    const yr = d.getFullYear();
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    return `${day} ${mon} ${yr} · ${hh}:${mm}`;
  }

  function renderStatusBadge(estado) {
    const map = {
      'Expediente Completo': {
        style: 'background: rgba(52, 199, 89, 0.13); color: #1b7a34;',
        dot: 'background: #34c759;',
        label: 'Completo'
      },
      'Pendiente Asignar Asesor (Academia)': {
        style: 'background: rgba(0, 122, 255, 0.12); color: #0066cc;',
        dot: 'background: #007aff;',
        label: 'Pendiente Asesor'
      },
      'En Trámite (Falta Oficio Asesor)': {
        style: 'background: rgba(0, 122, 255, 0.12); color: #0066cc;',
        dot: 'background: #007aff;',
        label: 'Falta Oficio P.B'
      },
      'En Revisión por Academia': {
        style: 'background: rgba(88, 86, 214, 0.12); color: #4b49b6;',
        dot: 'background: #5856d6;',
        label: 'Revisión Academia'
      },
      'Pausado / Sin Oficio': {
        style: 'background: rgba(255, 149, 0, 0.14); color: #b25000;',
        dot: 'background: #ff9500;',
        label: 'Pausado'
      },
      'Detenido por Servicio Social': {
        style: 'background: rgba(255, 59, 48, 0.13); color: #c92a2a;',
        dot: 'background: #ff3b30;',
        label: 'Detenido por S.S.'
      },
      'Caso Especial / Reasignación': {
        style: 'background: rgba(88, 86, 214, 0.12); color: #4b49b6;',
        dot: 'background: #5856d6;',
        label: 'Reasignación'
      }
    };

    const cfg = map[estado] || {
      style: 'background: rgba(118, 118, 128, 0.12); color: #6e6e73;',
      dot: 'background: #86868b;',
      label: estado || 'Sin estado'
    };

    return `<span class="status-badge" style="${cfg.style}"><span class="status-dot" style="${cfg.dot}"></span>${escapeHtml(cfg.label)}</span>`;
  }

  function renderSSBadge(servicioSocial, compact = false) {
    if (servicioSocial === 'Liberado') {
      if (compact) {
        return '<span class="inline-flex items-center gap-1 text-[11px] text-[#6e6e73]"><span class="material-symbols-outlined text-[13px] text-[#34c759]">check_circle</span>S.S. liberado</span>';
      }
      return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10.5px] font-medium" style="background: rgba(52, 199, 89, 0.12); color: #1b7a34;"><span class="material-symbols-outlined text-[12px]">verified</span>S.S. liberado</span>';
    }
    if (servicioSocial === 'No Liberado (Irregular)') {
      return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10.5px] font-semibold" style="background: rgba(255, 59, 48, 0.13); color: #c92a2a;"><span class="material-symbols-outlined text-[12px]">gpp_bad</span>S.S. no liberado</span>';
    }
    return '<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10.5px] font-medium" style="background: rgba(255, 149, 0, 0.14); color: #b25000;"><span class="material-symbols-outlined text-[12px]">help</span>S.S. por verificar</span>';
  }

  /**
   * 3 barras finas horizontales macOS + una línea limpia con folios P.A / P.B en .num-tabular
   */
  function renderPipelineMini(rec) {
    const isBlocked = rec.estado === 'Detenido por Servicio Social';
    const isPaused = rec.estado === 'Pausado / Sin Oficio';

    const s1Done = Boolean(rec.proyecto && rec.fechaEntregaFisica);
    const s2Done = Boolean(rec.oficioAutorizacion);
    const s3Done = Boolean(rec.asesorInterno && rec.oficioAsesorInterno);

    let c1 = s1Done ? 'is-done' : 'is-active';
    let c2 = s2Done ? 'is-done' : (s1Done ? 'is-active' : '');
    let c3 = s3Done ? 'is-done' : (rec.asesorInterno ? 'is-active' : '');

    if (isBlocked) {
      if (!s2Done) c2 = 'is-blocked';
      else c3 = 'is-blocked';
    } else if (isPaused) {
      if (!s2Done) c2 = 'is-paused';
      else if (!s3Done) c3 = 'is-paused';
    }

    const paText = rec.oficioAutorizacion ? escapeHtml(rec.oficioAutorizacion) : 'Sin P.A';
    const pbText = rec.oficioAsesorInterno ? escapeHtml(rec.oficioAsesorInterno) : 'Sin P.B';

    return `
      <div class="space-y-1.5" title="Etapa 1: Hojas Físicas | Etapa 2: Oficio P.A | Etapa 3: Asesor y Oficio P.B">
        <div class="mac-progress-3">
          <span class="mac-progress-seg ${c1}"></span>
          <span class="mac-progress-seg ${c2}"></span>
          <span class="mac-progress-seg ${c3}"></span>
        </div>
        <div class="num-tabular text-[11px] text-[#6e6e73]">
          <span class="${rec.oficioAutorizacion ? 'text-[#1d1d1f] font-medium' : ''}">${paText}</span>
          <span class="mx-1 text-[#aeaeb2]">·</span>
          <span class="${rec.oficioAsesorInterno ? 'text-[#1d1d1f] font-medium' : ''}">${pbText}</span>
        </div>
      </div>
    `;
  }

  function renderFullStepper(rec) {
    const s1 = Boolean(rec.proyecto && rec.fechaEntregaFisica);
    const s2 = Boolean(rec.oficioAutorizacion);
    const s3 = Boolean(rec.asesorInterno && rec.oficioAsesorInterno);
    const isWarn = rec.estado === 'Detenido por Servicio Social' || rec.estado === 'Pausado / Sin Oficio';

    const stepItem = (num, title, subtitle, done, active, warn) => {
      let iconColor = 'text-[#86868b]';
      let icon = 'radio_button_unchecked';
      if (done) {
        iconColor = 'text-[#1b7a34]';
        icon = 'check_circle';
      } else if (warn) {
        iconColor = 'text-[#c92a2a]';
        icon = 'error';
      } else if (active) {
        iconColor = 'text-[#007aff]';
        icon = 'pending';
      }
      return `
        <div class="p-3 bg-white flex flex-col justify-between gap-1">
          <div class="flex items-center justify-between gap-2">
            <span class="num-tabular text-[10px] font-semibold uppercase tracking-wider text-[#86868b]">Etapa ${num}</span>
            <span class="material-symbols-outlined text-[17px] ${iconColor}">${icon}</span>
          </div>
          <div class="text-[12px] font-semibold text-[#1d1d1f] leading-snug">${escapeHtml(title)}</div>
          <div class="text-[11px] num-tabular text-[#6e6e73]">${escapeHtml(subtitle)}</div>
        </div>
      `;
    };

    return `
      <div class="mac-group grid grid-cols-1 sm:grid-cols-3 divide-y sm:divide-y-0 sm:divide-x divide-black/[0.06]">
        ${stepItem(1, 'Hojas Impresas', s1 ? formatDateShort(rec.fechaEntregaFisica) : 'Sin entregar', s1, !s1, false)}
        ${stepItem(2, 'Gestión Acepta', rec.oficioAutorizacion || 'Pendiente P.A', s2, s1 && !s2, isWarn && !s2)}
        ${stepItem(3, 'Academia Asesor', rec.oficioAsesorInterno || (rec.asesorInterno ? 'Falta P.B' : 'Sin asesor'), s3, s2 && !s3, isWarn && s2 && !s3)}
      </div>
    `;
  }

  function renderTeacherLoadBar(activeCount, jornada) {
    const capMap = {
      '40 hrs': 4,
      '30 hrs': 3,
      '20 hrs': 2,
      'Por horas': 2
    };
    const cap = capMap[jornada] || 3;
    const pct = Math.min(100, Math.round((activeCount / cap) * 100));

    let barColor = '#34c759';
    let pillStyle = 'background: rgba(52, 199, 89, 0.13); color: #1b7a34;';
    let label = 'Disponible';

    if (activeCount >= cap + 1) {
      barColor = '#ff3b30';
      pillStyle = 'background: rgba(255, 59, 48, 0.13); color: #c92a2a;';
      label = 'Carga Alta';
    } else if (activeCount >= cap) {
      barColor = '#ff9500';
      pillStyle = 'background: rgba(255, 149, 0, 0.14); color: #b25000;';
      label = 'En Tope';
    }

    return `
      <div class="flex items-center gap-2.5 min-w-[155px]">
        <div class="flex-1">
          <div class="flex items-center justify-between text-[11px] num-tabular mb-1">
            <span class="font-semibold text-[#1d1d1f]">${activeCount} / ${cap}</span>
            <span class="px-1.5 py-0.2 rounded-full text-[10px] font-medium" style="${pillStyle}">${label}</span>
          </div>
          <div class="w-full h-[5px] rounded-full bg-black/[0.08] overflow-hidden">
            <div class="h-full rounded-full transition-all" style="width: ${pct}%; background: ${barColor};"></div>
          </div>
        </div>
      </div>
    `;
  }

  let toastTimer = null;
  function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const iconMap = {
      info: { icon: 'info', color: '#64d2ff' },
      success: { icon: 'check_circle', color: '#30d158' },
      warning: { icon: 'warning', color: '#ffd60a' },
      error: { icon: 'error', color: '#ff453a' }
    };
    const cfg = iconMap[type] || iconMap.info;

    container.className = 'fixed bottom-5 right-5 z-[80] max-w-sm rounded-full px-4 py-2.5 shadow-2xl flex items-center gap-2 text-xs font-medium text-white border border-white/15 transition-all';
    container.style.background = 'rgba(29, 29, 31, 0.90)';
    container.style.backdropFilter = 'blur(16px)';
    container.style.webkitBackdropFilter = 'blur(16px)';
    container.innerHTML = `<span class="material-symbols-outlined text-[16px] shrink-0" style="color:${cfg.color}">${cfg.icon}</span><span>${escapeHtml(message)}</span>`;
    container.classList.remove('hidden');

    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      container.classList.add('hidden');
    }, 3200);
  }

  global.ResidenciasUI = {
    escapeHtml,
    formatPersonName,
    formatTitleText,
    formatDateShort,
    formatDateTimeShort,
    renderStatusBadge,
    renderSSBadge,
    renderPipelineMini,
    renderFullStepper,
    renderTeacherLoadBar,
    showToast
  };
})(window);
