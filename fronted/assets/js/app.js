/**
 * App Controller: Sistema Integral de Control de Residencias Profesionales
 * Ingeniería Industrial · TecNM (macOS Desktop UI)
 */
(function (global) {
  'use strict';

  const Store = global.ResidenciasStore;
  const UI = global.ResidenciasUI;

  const appState = {
    activeView: 'expedientes',
    academiaSubtab: 'bandeja',   // 'bandeja' | 'docentes'
    excepcionesSubtab: 'pausados', // 'pausados' | 'ss'
    oficiosSubtab: 'pendientes', // 'pendientes' | 'emitidos'
    selectedId: null,
    academiaEditUnlocked: false,
    advancedFiltersOpen: false,
    tableDensity: 'comfortable', // 'comfortable' | 'compact'
    pageSize: 20,
    currentPage: 1,
    filters: {
      q: '',
      semestre: 'ALL',
      estado: 'ALL',
      servicioSocial: 'ALL',
      especialidad: 'ALL',
      asesor: 'ALL',
      empresa: 'ALL',
      oficioFilter: 'ALL',
      sortBy: 'id',
      sortDir: 'asc'
    },
    maestrosFilter: {
      q: '',
      jornada: 'ALL',
      beca: 'ALL'
    },
    bitacoraFilter: {
      q: '',
      usuario: 'ALL'
    }
  };

  // =========================================================================
  // Configuración de Navegación por Rol (Etiquetas limpias sin truncado)
  // =========================================================================
  function getSidebarItemsForRole(roleMeta, kpis) {
    if (roleMeta.isAcademia) {
      return [
        {
          id: 'academia',
          subtab: 'bandeja',
          label: 'Bandeja Academia',
          icon: 'school',
          badge: kpis.pendientesAcademia,
          badgeStyle: kpis.pendientesAcademia > 0
            ? 'background: rgba(88, 86, 214, 0.14); color: #4b49b6;'
            : 'background: rgba(0,0,0,0.06); color: #6e6e73;'
        },
        {
          id: 'docentes',
          subtab: 'docentes',
          label: 'Carga Docente',
          icon: 'groups',
          badge: Store.getMaestros().length,
          badgeStyle: 'background: rgba(0,0,0,0.06); color: #6e6e73;'
        },
        {
          id: 'expedientes',
          label: 'Expedientes',
          icon: 'folder_shared',
          badge: kpis.total,
          badgeStyle: 'background: rgba(0,0,0,0.06); color: #6e6e73;'
        },
        {
          id: 'excepciones',
          label: 'Excepciones y S.S.',
          icon: 'warning',
          badge: kpis.pausados + kpis.alertasSS,
          badgeStyle: 'background: rgba(255, 59, 48, 0.12); color: #c92a2a;'
        },
        {
          id: 'bitacora',
          label: 'Bitácora',
          icon: 'history'
        }
      ];
    }

    return [
      {
        id: 'expedientes',
        label: 'Expedientes',
        icon: 'folder_shared',
        badge: kpis.total,
        badgeStyle: 'background: rgba(0,0,0,0.06); color: #6e6e73;'
      },
      {
        id: 'registro',
        label: 'Registrar Solicitud',
        icon: 'note_add'
      },
      {
        id: 'oficios',
        label: 'Emisión de Oficios',
        icon: 'description',
        badge: kpis.pendientesGestionOficio,
        badgeStyle: kpis.pendientesGestionOficio > 0
          ? 'background: rgba(255, 149, 0, 0.15); color: #b25000;'
          : 'background: rgba(0,0,0,0.06); color: #6e6e73;'
      },
      {
        id: 'excepciones',
        label: 'Pausados y S.S.',
        icon: 'warning',
        badge: kpis.pausados + kpis.alertasSS,
        badgeStyle: (kpis.pausados + kpis.alertasSS) > 0
          ? 'background: rgba(255, 59, 48, 0.12); color: #c92a2a;'
          : 'background: rgba(0,0,0,0.06); color: #6e6e73;'
      },
      {
        id: 'docentes',
        subtab: 'docentes',
        label: 'Docentes',
        icon: 'school',
        badge: Store.getMaestros().length,
        badgeStyle: 'background: rgba(0,0,0,0.06); color: #6e6e73;'
      },
      {
        id: 'bitacora',
        label: 'Bitácora',
        icon: 'history'
      }
    ];
  }

  function renderSidebar() {
    const roleMeta = Store.getRoleMeta();
    const kpis = Store.getKPIs();
    const navEl = document.getElementById('sidebar-nav');
    if (!navEl) return;

    document.body.classList.toggle('role-academia', roleMeta.isAcademia);

    const items = getSidebarItemsForRole(roleMeta, kpis);
    navEl.innerHTML = items.map((item) => {
      const isCurrent =
        (item.id === 'docentes' && appState.activeView === 'academia' && appState.academiaSubtab === 'docentes') ||
        (item.id === 'academia' && appState.activeView === 'academia' && appState.academiaSubtab === 'bandeja') ||
        (item.id === appState.activeView && item.id !== 'academia' && item.id !== 'docentes');

      const badgeHtml = item.badge !== undefined
        ? `<span class="num-tabular text-[10.5px] font-semibold px-1.5 py-0.5 rounded-full shrink-0" style="${item.badgeStyle}">${item.badge}</span>`
        : '';

      return `
        <button type="button"
          class="sidebar-nav-item ${isCurrent ? 'is-active' : ''}"
          data-action="navigate"
          data-view="${item.id}"
          ${item.subtab ? `data-subtab="${item.subtab}"` : ''}>
          <span class="flex items-center gap-2 min-w-0">
            <span class="material-symbols-outlined text-[17px] shrink-0">${item.icon}</span>
            <span class="truncate">${UI.escapeHtml(item.label)}</span>
          </span>
          ${badgeHtml}
        </button>
      `;
    }).join('');

    const roleCardDesc = document.getElementById('sidebar-role-desc');
    if (roleCardDesc) roleCardDesc.textContent = roleMeta.subtitle;

    ['gestion1', 'academia'].forEach((rId) => {
      const btn = document.getElementById(`role-btn-${rId}`);
      if (!btn) return;
      btn.classList.toggle('is-active', rId === roleMeta.id);
    });

    const footerRole = document.getElementById('footer-role-indicator');
    const connInfo = Store.getConnectionInfo();
    if (footerRole) footerRole.textContent = `${roleMeta.label} · ${connInfo.modeLabel}`;
  }

  function renderTopbar() {
    const roleMeta = Store.getRoleMeta();
    const kpis = Store.getKPIs();
    const titleEl = document.getElementById('topbar-title');
    const subtitleEl = document.getElementById('topbar-subtitle');
    const ctaEl = document.getElementById('topbar-primary-cta');

    const viewTitles = {
      expedientes: {
        title: 'Expedientes y Consultas',
        sub: 'Búsqueda multicampo sobre solicitudes impresas, oficios, asesores y avisos Outlook'
      },
      registro: {
        title: 'Recepción de Solicitud Física',
        sub: 'Captura de anteproyecto impreso, correo institucional y estatus de Servicio Social'
      },
      oficios: {
        title: 'Emisión de Oficios (P.A y P.B) y Avisos Outlook',
        sub: 'Autorización de anteproyectos, folios consecutivos, impresión y envío de aviso'
      },
      academia: {
        title: appState.academiaSubtab === 'docentes'
          ? 'Directorio y Carga Docente (42)'
          : 'Usuario 2 · Academia · Asignación de Asesores',
        sub: 'Dictamen técnico de anteproyectos y distribución equitativa de asesores'
      },
      excepciones: {
        title: 'Trámites Pausados y Servicio Social',
        sub: 'Proyectos inconclusos, reasignaciones y expedientes detenidos por falta de S.S.'
      },
      bitacora: {
        title: 'Bitácora de Movimientos',
        sub: 'Historial cronológico de altas, oficios, asignaciones y avisos por Outlook'
      }
    };

    const meta = viewTitles[appState.activeView] || viewTitles.expedientes;
    if (titleEl) titleEl.textContent = meta.title;
    if (subtitleEl) subtitleEl.textContent = meta.sub;

    if (ctaEl) {
      if (roleMeta.isAcademia) {
        ctaEl.innerHTML = `
          <button type="button" data-action="navigate" data-view="academia" data-subtab="bandeja"
            class="mac-btn-primary is-academia">
            <span class="material-symbols-outlined text-[15px]">school</span>
            <span>Pendientes (${kpis.pendientesAcademia})</span>
          </button>
        `;
      } else {
        ctaEl.innerHTML = `
          <button type="button" data-action="new-solicitud" class="mac-btn-primary">
            <span class="material-symbols-outlined text-[15px]">add</span>
            <span>Registrar Solicitud</span>
          </button>
        `;
      }
    }
  }

  // =========================================================================
  // Navegación entre Vistas
  // =========================================================================
  function navigateTo(view, subtab) {
    if (view === 'docentes') {
      appState.activeView = 'academia';
      appState.academiaSubtab = 'docentes';
    } else {
      appState.activeView = view;
      if (view === 'academia' && subtab) {
        appState.academiaSubtab = subtab;
      }
    }

    document.querySelectorAll('[data-view-panel]').forEach((el) => {
      el.hidden = el.dataset.viewPanel !== appState.activeView;
    });

    closeMobileSidebar();
    renderSidebar();
    renderTopbar();
    renderActiveView();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function renderActiveView() {
    switch (appState.activeView) {
      case 'expedientes':
        renderExpedientesView();
        break;
      case 'registro':
        renderRegistroViewSetup();
        break;
      case 'oficios':
        renderOficiosView();
        break;
      case 'academia':
        renderAcademiaView();
        break;
      case 'excepciones':
        renderExcepcionesView();
        break;
      case 'bitacora':
        renderBitacoraView();
        break;
      default:
        renderExpedientesView();
    }
  }

  // =========================================================================
  // VISTA 1: EXPEDIENTES Y CONSULTAS UNIVERSALES
  // =========================================================================
  function populateFilterDropdowns() {
    const semSel = document.getElementById('filter-semestre');
    const aseSel = document.getElementById('filter-asesor');
    const espSel = document.getElementById('filter-especialidad');
    const empSel = document.getElementById('filter-empresa');

    if (semSel) {
      const current = appState.filters.semestre;
      semSel.innerHTML = '<option value="ALL">Semestre: Todos</option>' +
        Store.getUniqueSemestres().map((s) => `<option value="${UI.escapeHtml(s)}">${UI.escapeHtml(s)}</option>`).join('');
      semSel.value = current;
    }

    if (aseSel) {
      const current = appState.filters.asesor;
      aseSel.innerHTML = '<option value="ALL">Asesor Interno: Todos</option><option value="SIN_ASESOR">-- Sin Asesor Asignado --</option>' +
        Store.getUniqueAsesores().map((a) => `<option value="${UI.escapeHtml(a)}">${UI.escapeHtml(UI.formatPersonName(a))}</option>`).join('');
      aseSel.value = current;
    }

    if (espSel) {
      const current = appState.filters.especialidad;
      espSel.innerHTML = '<option value="ALL">Especialidad: Todas</option>' +
        Store.getUniqueEspecialidades().map((e) => `<option value="${UI.escapeHtml(e)}">${UI.escapeHtml(UI.formatTitleText(e))}</option>`).join('');
      espSel.value = current;
    }

    if (empSel) {
      const current = appState.filters.empresa;
      empSel.innerHTML = '<option value="ALL">Empresa: Todas (97)</option>' +
        Store.getUniqueEmpresas().map((e) => `<option value="${UI.escapeHtml(e)}">${UI.escapeHtml(UI.formatTitleText(e))}</option>`).join('');
      empSel.value = current;
    }
  }

  function renderExpedientesKPIs() {
    const kpis = Store.getKPIs();
    const roleMeta = Store.getRoleMeta();
    const container = document.getElementById('expedientes-kpis');
    if (!container) return;

    const cards = roleMeta.isAcademia
      ? [
          {
            label: 'Total Expedientes',
            val: kpis.total,
            sub: 'Ver todos los registros',
            dot: '#007aff',
            filter: { estado: 'ALL', servicioSocial: 'ALL' }
          },
          {
            label: 'Pendientes de Academia',
            val: kpis.pendientesAcademia,
            sub: 'Sin asesor o falta oficio P.B',
            dot: '#5856d6',
            filter: { estado: 'PENDIENTE_ACADEMIA', servicioSocial: 'ALL' }
          },
          {
            label: 'Expedientes Completos',
            val: kpis.completos,
            sub: 'Asesor y oficios listos',
            dot: '#34c759',
            filter: { estado: 'Expediente Completo', servicioSocial: 'ALL' }
          },
          {
            label: 'Alertas S.S. / Pausados',
            val: kpis.alertasSS,
            sub: 'Por verificar o bloqueados',
            dot: '#ff3b30',
            filter: { estado: 'ALL', servicioSocial: 'SIN_SS' }
          }
        ]
      : [
          {
            label: 'Total Expedientes',
            val: kpis.total,
            sub: 'Solicitudes físicas capturadas',
            dot: '#007aff',
            filter: { estado: 'ALL', servicioSocial: 'ALL' }
          },
          {
            label: 'Expedientes Completos',
            val: kpis.completos,
            sub: 'Flujo 3 etapas concluido',
            dot: '#34c759',
            filter: { estado: 'Expediente Completo', servicioSocial: 'ALL' }
          },
          {
            label: 'Pendientes Oficio / Asesor',
            val: kpis.pendientesGestionOficio + kpis.sinAsesor,
            sub: `${kpis.pendientesGestionOficio} sin oficio · ${kpis.sinAsesor} sin asesor`,
            dot: '#5856d6',
            filter: { estado: 'PENDIENTE_ACADEMIA', servicioSocial: 'ALL' }
          },
          {
            label: 'Pausados / Alertas S.S.',
            val: kpis.pausados + kpis.alertasSS,
            sub: `${kpis.pausados} pausados · ${kpis.alertasSS} alertas S.S.`,
            dot: '#ff9500',
            filter: { estado: 'Pausado / Sin Oficio', servicioSocial: 'ALL' }
          }
        ];

    container.innerHTML = cards.map((c, idx) => `
      <button type="button" data-action="kpi-filter" data-kpi-idx="${idx}"
        class="mac-card p-3.5 text-left hover:border-black/20 hover:shadow-sm transition flex flex-col justify-between gap-1">
        <div class="flex items-center justify-between gap-2 w-full">
          <span class="text-[11.5px] font-medium text-[#6e6e73]">${UI.escapeHtml(c.label)}</span>
          <span class="w-2 h-2 rounded-full shrink-0" style="background:${c.dot}"></span>
        </div>
        <div class="text-[24px] font-semibold num-tabular text-[#1d1d1f] leading-tight mt-0.5">${c.val}</div>
        <div class="text-[11px] text-[#86868b]">${UI.escapeHtml(c.sub)}</div>
      </button>
    `).join('');

    container._cards = cards;
  }

  function renderActiveFilterChips() {
    const chipsEl = document.getElementById('active-filter-chips');
    if (!chipsEl) return;

    const f = appState.filters;
    const chips = [];
    if (f.q) chips.push({ key: 'q', label: `Búsqueda: "${f.q}"` });
    if (f.semestre !== 'ALL') chips.push({ key: 'semestre', label: `Semestre: ${f.semestre}` });
    if (f.estado !== 'ALL') chips.push({ key: 'estado', label: `Estado: ${f.estado === 'PENDIENTE_ACADEMIA' ? 'Pendiente Academia/Oficio' : f.estado}` });
    if (f.servicioSocial !== 'ALL') chips.push({ key: 'servicioSocial', label: `S.S.: ${f.servicioSocial === 'SIN_SS' ? 'Por verificar / No liberado' : f.servicioSocial}` });
    if (f.asesor !== 'ALL') chips.push({ key: 'asesor', label: `Asesor: ${f.asesor === 'SIN_ASESOR' ? 'Sin asesor' : UI.formatPersonName(f.asesor)}` });
    if (f.especialidad !== 'ALL') chips.push({ key: 'especialidad', label: `Especialidad: ${UI.formatTitleText(f.especialidad)}` });
    if (f.empresa !== 'ALL') chips.push({ key: 'empresa', label: `Empresa: ${UI.formatTitleText(f.empresa)}` });
    if (f.oficioFilter !== 'ALL') chips.push({ key: 'oficioFilter', label: `Oficios: ${f.oficioFilter}` });

    if (chips.length === 0) {
      chipsEl.innerHTML = '';
      chipsEl.classList.add('hidden');
      return;
    }

    chipsEl.classList.remove('hidden');
    chipsEl.innerHTML = chips.map((ch) => `
      <button type="button" data-action="remove-chip" data-chip-key="${ch.key}"
        class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-black/[0.05] hover:bg-black/[0.09] text-[#1d1d1f] text-[11px] font-medium transition">
        <span>${UI.escapeHtml(ch.label)}</span>
        <span class="text-[#86868b]">✕</span>
      </button>
    `).join('') + `
      <button type="button" data-action="clear-filters"
        class="text-[11px] font-semibold text-[#007aff] hover:underline px-1.5 py-0.5">
        Limpiar todos
      </button>
    `;
  }

  function syncFilterInputsFromState() {
    const f = appState.filters;
    const setVal = (id, v) => {
      const el = document.getElementById(id);
      if (el) el.value = v;
    };
    setVal('filter-q', f.q);
    setVal('filter-semestre', f.semestre);
    setVal('filter-estado', f.estado);
    setVal('filter-ss', f.servicioSocial);
    setVal('filter-asesor', f.asesor);
    setVal('filter-especialidad', f.especialidad);
    setVal('filter-empresa', f.empresa);
    setVal('filter-oficio', f.oficioFilter);
    setVal('sort-by', f.sortBy);
    setVal('page-size', String(appState.pageSize));
  }

  function renderExpedientesView() {
    populateFilterDropdowns();
    syncFilterInputsFromState();
    renderExpedientesKPIs();
    renderActiveFilterChips();

    const allResults = Store.queryExpedientes(appState.filters);
    const totalFiltered = allResults.length;
    const totalAll = Store.getResidencias().length;

    const pageSize = appState.pageSize === 0 ? Math.max(1, totalFiltered) : appState.pageSize;
    const totalPages = Math.max(1, Math.ceil(totalFiltered / pageSize));
    if (appState.currentPage > totalPages) appState.currentPage = totalPages;

    const startIdx = (appState.currentPage - 1) * pageSize;
    const pageRows = appState.pageSize === 0 ? allResults : allResults.slice(startIdx, startIdx + pageSize);

    const summaryEl = document.getElementById('results-counter');
    if (summaryEl) {
      summaryEl.textContent = totalFiltered === 0
        ? '0 resultados'
        : `Mostrando ${startIdx + 1}–${startIdx + pageRows.length} de ${totalFiltered} expedientes (${totalAll} en BD)`;
    }

    const pageInfoEl = document.getElementById('pagination-info');
    if (pageInfoEl) {
      pageInfoEl.textContent = `Página ${appState.currentPage} de ${totalPages}`;
    }

    const prevBtn = document.getElementById('btn-prev-page');
    const nextBtn = document.getElementById('btn-next-page');
    if (prevBtn) prevBtn.disabled = appState.currentPage <= 1;
    if (nextBtn) nextBtn.disabled = appState.currentPage >= totalPages;

    const tableEl = document.getElementById('expedientes-table');
    if (tableEl) {
      tableEl.classList.toggle('is-compact', appState.tableDensity === 'compact');
    }

    const tbody = document.getElementById('expedientes-tbody');
    if (!tbody) return;

    if (pageRows.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="6" class="py-14 text-center">
            <div class="inline-flex flex-col items-center gap-2 max-w-sm">
              <span class="material-symbols-outlined text-4xl text-[#aeaeb2]">search_off</span>
              <div class="text-sm font-semibold text-[#1d1d1f]">Sin coincidencias</div>
              <p class="text-xs text-[#6e6e73]">Intenta limpiar los filtros o buscar por número de control o apellido.</p>
              <button type="button" data-action="clear-filters" class="mt-2 mac-btn-secondary">
                Restablecer filtros
              </button>
            </div>
          </td>
        </tr>
      `;
      return;
    }

    tbody.innerHTML = pageRows.map((r) => {
      const projectCell = r.proyecto
        ? `<div class="font-medium text-[#1d1d1f] line-clamp-2 leading-snug max-w-md">${UI.escapeHtml(UI.formatTitleText(r.proyecto))}</div>
           <div class="text-[11.5px] text-[#6e6e73] mt-0.5 flex flex-wrap items-center gap-1.5">
             <span>${UI.escapeHtml(UI.formatTitleText(r.empresa || 'Sin empresa'))}</span>
             ${r.periodo ? `<span class="text-[#aeaeb2]">·</span><span class="num-tabular text-[11px]">${UI.escapeHtml(UI.formatTitleText(r.periodo))}</span>` : ''}
           </div>`
        : '<div class="text-xs text-[#6e6e73]">Sin título de anteproyecto</div>';

      const advisorDisplay = r.asesorInterno ? UI.formatPersonName(r.asesorInterno) : 'Sin asignar';
      const extAdvisorDisplay = r.asesorExterno ? UI.formatPersonName(r.asesorExterno) : '';

      return `
        <tr class="clickable-row" data-action="open-detail" data-id="${r.id}">
          <td class="whitespace-nowrap">
            <div class="num-tabular font-semibold text-[#1d1d1f] text-[12.5px]">${UI.escapeHtml(r.control)}</div>
            <div class="num-tabular text-[11px] text-[#6e6e73] mt-0.5 flex items-center gap-1">
              <span>#${r.id}</span>
              <span>·</span>
              <span>${UI.escapeHtml(r.semestre)}</span>
            </div>
          </td>
          <td>
            <div class="font-semibold text-[#1d1d1f] leading-snug">${UI.escapeHtml(UI.formatPersonName(r.nombre))}</div>
            <div class="text-[11px] text-[#6e6e73] mt-0.5 truncate max-w-[230px]">${UI.escapeHtml(r.correoInstitucional || UI.formatTitleText(r.especialidad))}</div>
          </td>
          <td>${projectCell}</td>
          <td class="whitespace-nowrap">
            ${UI.renderPipelineMini(r)}
            <div class="num-tabular text-[10.5px] text-[#86868b] mt-0.5">
              ${r.fechaEntregaFisica ? `Recibido ${UI.formatDateShort(r.fechaEntregaFisica)}` : 'Sin fecha física'}
            </div>
          </td>
          <td>
            <div class="font-medium text-[12px] ${r.asesorInterno ? 'text-[#1d1d1f]' : 'text-[#c92a2a]'}">
              ${UI.escapeHtml(advisorDisplay)}
            </div>
            <div class="num-tabular text-[11px] text-[#6e6e73] mt-0.5">
              ${r.folioAcademia ? `Folio ${UI.escapeHtml(r.folioAcademia)}` : (extAdvisorDisplay ? `Ext: ${UI.escapeHtml(extAdvisorDisplay.slice(0, 26))}` : '—')}
            </div>
          </td>
          <td class="whitespace-nowrap">
            <div class="space-y-1">
              <div>${UI.renderStatusBadge(r.estado)}</div>
              <div>${UI.renderSSBadge(r.servicioSocial, true)}</div>
            </div>
          </td>
        </tr>
      `;
    }).join('');
  }

  // =========================================================================
  // VISTA 2: FORMULARIO DE CAPTURA DE HOJAS IMPRESAS
  // =========================================================================
  function populateFormDatalists() {
    const empList = document.getElementById('empresas-datalist');
    if (empList) {
      empList.innerHTML = Store.getUniqueEmpresas()
        .map((e) => `<option value="${UI.escapeHtml(e)}"></option>`)
        .join('');
    }
    const aseSel = document.getElementById('f-asesor-int');
    if (aseSel) {
      const current = aseSel.value;
      const maestros = Store.getMaestros().slice().sort((a, b) =>
        Store.countActiveForTeacher(a.nombre) - Store.countActiveForTeacher(b.nombre)
      );
      aseSel.innerHTML = '<option value="">-- Sin asignar todavía --</option>' +
        maestros.map((m) => {
          const active = Store.countActiveForTeacher(m.nombre);
          return `<option value="${UI.escapeHtml(m.nombre.toUpperCase())}">${UI.escapeHtml(UI.formatPersonName(m.nombre))} (${active} activos · ${UI.escapeHtml(m.jornada)})</option>`;
        }).join('');
      if (current) {
        const upper = current.toUpperCase();
        if (!Array.from(aseSel.options).some((o) => o.value === upper)) {
          const opt = document.createElement('option');
          opt.value = upper;
          opt.textContent = UI.formatPersonName(upper);
          aseSel.appendChild(opt);
        }
        aseSel.value = upper;
      }
    }
  }

  function applyRolePermissionsToForm() {
    const roleMeta = Store.getRoleMeta();
    const isAcademia = roleMeta.isAcademia;

    const gestionSections = ['form-sec-alumno', 'form-sec-proyecto', 'form-sec-gestion'];
    gestionSections.forEach((secId) => {
      const sec = document.getElementById(secId);
      if (!sec) return;
      const banner = sec.querySelector('.readonly-section-banner');
      if (banner) banner.classList.toggle('hidden', !isAcademia);
      sec.querySelectorAll('input, select, textarea').forEach((el) => {
        if (el.id === 'f-id') return;
        el.disabled = isAcademia;
        el.classList.toggle('field-locked', isAcademia);
      });
    });

    const acadSec = document.getElementById('form-sec-academia');
    const toggleBtn = document.getElementById('btn-unlock-academia-fields');
    if (acadSec) {
      const lockedForGestion = !isAcademia && !appState.academiaEditUnlocked;
      if (toggleBtn) {
        toggleBtn.classList.toggle('hidden', isAcademia);
        toggleBtn.innerHTML = appState.academiaEditUnlocked
          ? '<span class="material-symbols-outlined text-[14px]">lock_open</span> Bloquear sección Academia'
          : '<span class="material-symbols-outlined text-[14px]">edit</span> Habilitar corrección Academia';
      }
      acadSec.querySelectorAll('input, select').forEach((el) => {
        el.disabled = lockedForGestion;
        el.classList.toggle('field-locked', lockedForGestion);
      });
    }
  }

  function syncSSRadioCards(val) {
    document.querySelectorAll('.ss-radio-card').forEach((card) => {
      const radio = card.querySelector('input[type="radio"]');
      if (!radio) return;
      const checked = radio.value === val;
      radio.checked = checked;
      card.classList.remove('is-selected-ok', 'is-selected-warn', 'is-selected-danger');
      if (checked) {
        if (val === 'Liberado') card.classList.add('is-selected-ok');
        else if (val === 'No Liberado (Irregular)') card.classList.add('is-selected-danger');
        else card.classList.add('is-selected-warn');
      }
    });
  }

  function updateFormLivePreview() {
    const control = document.getElementById('f-control')?.value.trim() || '—';
    const nombre = document.getElementById('f-nombre')?.value.trim() || 'Nombre del alumno';
    const proyecto = document.getElementById('f-proyecto')?.value.trim() || 'Sin anteproyecto capturado';
    const empresa = document.getElementById('f-empresa')?.value.trim() || 'Sin empresa';
    const oficioPA = document.getElementById('f-oficio-aut')?.value.trim() || '';
    const oficioPB = document.getElementById('f-oficio-asesor')?.value.trim() || '';
    const asesor = document.getElementById('f-asesor-int')?.value.trim() || '';
    const ss = document.querySelector('input[name="f-ss-radio"]:checked')?.value || 'Por verificar';
    const estado = document.getElementById('f-estado')?.value || 'En Revisión por Academia';

    const previewEl = document.getElementById('form-live-preview');
    if (!previewEl) return;

    previewEl.innerHTML = `
      <div class="space-y-3">
        <div class="flex items-center justify-between gap-2">
          <span class="num-tabular text-xs font-semibold text-[#007aff] bg-[#007aff]/10 px-2 py-0.5 rounded-md">${UI.escapeHtml(control)}</span>
          ${UI.renderSSBadge(ss)}
        </div>
        <div>
          <div class="text-[13px] font-semibold text-[#1d1d1f] leading-snug">${UI.escapeHtml(UI.formatPersonName(nombre))}</div>
          <div class="text-xs text-[#6e6e73] mt-0.5">${UI.escapeHtml(UI.formatTitleText(empresa))}</div>
        </div>
        <div class="p-2.5 rounded-lg bg-[#f5f5f7] border border-black/[0.06] text-[12px] text-[#1d1d1f] leading-snug">
          ${UI.escapeHtml(UI.formatTitleText(proyecto))}
        </div>
        <div class="mac-group">
          <div class="mac-group-row">
            <span class="text-[#6e6e73]">Estado</span>
            <span>${UI.renderStatusBadge(estado)}</span>
          </div>
          <div class="mac-group-row">
            <span class="text-[#6e6e73]">Oficio Aut. (P.A)</span>
            <span class="num-tabular font-semibold text-[#1d1d1f]">${UI.escapeHtml(oficioPA || 'Pendiente')}</span>
          </div>
          <div class="mac-group-row">
            <span class="text-[#6e6e73]">Asesor Interno</span>
            <span class="font-medium text-[#1d1d1f] text-right max-w-[170px] truncate">${UI.escapeHtml(asesor ? UI.formatPersonName(asesor) : 'Sin asignar')}</span>
          </div>
          <div class="mac-group-row">
            <span class="text-[#6e6e73]">Oficio Asesor (P.B)</span>
            <span class="num-tabular font-semibold text-[#1d1d1f]">${UI.escapeHtml(oficioPB || 'Pendiente')}</span>
          </div>
        </div>
      </div>
    `;
  }

  function renderRegistroViewSetup() {
    populateFormDatalists();
    applyRolePermissionsToForm();
    updateFormLivePreview();
  }

  function resetSolicitudForm() {
    const form = document.getElementById('form-solicitud');
    if (form) form.reset();
    document.getElementById('f-id').value = '';
    document.getElementById('f-fecha-fisica').value = Store.todayISO();
    document.getElementById('f-semestre').value = 'Ago-Dic 2026';
    document.getElementById('f-estado').value = 'En Revisión por Academia';
    syncSSRadioCards('Liberado');
    const hint = document.getElementById('f-control-hint');
    if (hint) {
      hint.className = 'text-[11px] text-[#6e6e73] mt-1';
      hint.textContent = 'Verifica si el estudiante ya tiene expediente físico previo.';
    }
    const modeBadge = document.getElementById('form-mode-badge');
    if (modeBadge) modeBadge.textContent = 'Nueva Solicitud Física';
    appState.academiaEditUnlocked = false;
    renderRegistroViewSetup();
  }

  function loadRecordIntoForm(id) {
    const r = Store.getById(id);
    if (!r) return;
    navigateTo('registro');
    populateFormDatalists();

    document.getElementById('f-id').value = r.id;
    document.getElementById('f-control').value = r.control;
    document.getElementById('f-nombre').value = r.nombre;
    const correoEl = document.getElementById('f-correo');
    if (correoEl) correoEl.value = r.correoInstitucional || (r.control ? `l${r.control}@cdmadero.tecnm.mx` : '');
    document.getElementById('f-semestre').value = r.semestre || 'Ago-Dic 2026';
    document.getElementById('f-especialidad').value = r.especialidad || 'INDUSTRIAL GENERAL';
    document.getElementById('f-proyecto').value = r.proyecto || '';
    document.getElementById('f-empresa').value = r.empresa || '';
    document.getElementById('f-asesor-ext').value = r.asesorExterno || '';
    document.getElementById('f-horario').value = r.horario || '';
    document.getElementById('f-periodo').value = r.periodo || '';
    document.getElementById('f-fecha-fisica').value = /^\d{4}-\d{2}-\d{2}$/.test(r.fechaEntregaFisica) ? r.fechaEntregaFisica : Store.todayISO();
    document.getElementById('f-fecha-academia').value = /^\d{4}-\d{2}-\d{2}$/.test(r.fechaEntregaAcademia) ? r.fechaEntregaAcademia : '';
    document.getElementById('f-oficio-aut').value = r.oficioAutorizacion || '';
    document.getElementById('f-fecha-imp').value = /^\d{4}-\d{2}-\d{2}$/.test(r.fechaImpresion) ? r.fechaImpresion : '';
    document.getElementById('f-notificado').value = /^\d{4}-\d{2}-\d{2}$/.test(r.notificadoAlumno) ? r.notificadoAlumno : '';
    document.getElementById('f-fecha-aut-correo').value = /^\d{4}-\d{2}-\d{2}$/.test(r.fechaEnvioAutCorreo) ? r.fechaEnvioAutCorreo : '';
    document.getElementById('f-estado').value = r.estado || 'En Revisión por Academia';
    document.getElementById('f-observaciones').value = r.observaciones || '';
    document.getElementById('f-revisado-acad').value = r.revisadoAcademia || 'Pendiente';

    const aseSel = document.getElementById('f-asesor-int');
    const upperAse = (r.asesorInterno || '').toUpperCase();
    if (upperAse && !Array.from(aseSel.options).some((o) => o.value === upperAse)) {
      const opt = document.createElement('option');
      opt.value = upperAse;
      opt.textContent = UI.formatPersonName(upperAse);
      aseSel.appendChild(opt);
    }
    aseSel.value = upperAse;
    document.getElementById('f-folio-acad').value = r.folioAcademia || '';
    document.getElementById('f-oficio-asesor').value = r.oficioAsesorInterno || '';
    document.getElementById('f-fecha-asesor-correo').value = /^\d{4}-\d{2}-\d{2}$/.test(r.fechaEnvioAsesorCorreo) ? r.fechaEnvioAsesorCorreo : '';

    const ssVal = r.servicioSocial === 'Liberado'
      ? 'Liberado'
      : (r.servicioSocial === 'No Liberado (Irregular)' ? 'No Liberado (Irregular)' : 'Por verificar');
    syncSSRadioCards(ssVal);

    const hint = document.getElementById('f-control-hint');
    if (hint) {
      hint.className = 'text-[11px] font-semibold text-[#007aff] mt-1';
      hint.textContent = `Editando expediente existente #${r.id}.`;
    }

    const modeBadge = document.getElementById('form-mode-badge');
    if (modeBadge) modeBadge.textContent = `Editando Expediente #${r.id}`;

    renderRegistroViewSetup();
  }

  function handleControlLookup(val) {
    const clean = val.trim();
    const hint = document.getElementById('f-control-hint');
    const correoEl = document.getElementById('f-correo');
    const currentId = document.getElementById('f-id').value;
    if (!hint) return;
    if (clean.length < 6) {
      hint.className = 'text-[11px] text-[#6e6e73] mt-1';
      hint.textContent = 'Verifica si el estudiante ya tiene expediente físico previo.';
      return;
    }

    if (correoEl && !correoEl.value.trim()) {
      correoEl.value = `l${clean}@cdmadero.tecnm.mx`.toLowerCase();
    }

    const found = Store.findByControl(clean);
    if (found && String(found.id) !== String(currentId)) {
      document.getElementById('f-id').value = found.id;
      document.getElementById('f-nombre').value = found.nombre;
      if (correoEl && found.correoInstitucional) correoEl.value = found.correoInstitucional;
      hint.className = 'text-[11px] font-semibold text-[#1b7a34] mt-1';
      hint.textContent = `Encontrado en BD (${found.estado}). Se actualizará #${found.id}.`;
    } else if (!found) {
      hint.className = 'text-[11px] font-medium text-[#007aff] mt-1';
      hint.textContent = 'N° de control nuevo — se registrará nuevo expediente físico.';
    }
    updateFormLivePreview();
  }

  async function handleSaveSolicitudForm(event) {
    event.preventDefault();
    const roleMeta = Store.getRoleMeta();
    const idVal = document.getElementById('f-id').value;

    if (roleMeta.isAcademia && idVal) {
      try {
        const asesor = document.getElementById('f-asesor-int').value;
        const folioAcad = document.getElementById('f-folio-acad').value;
        const dictamen = document.getElementById('f-revisado-acad').value;
        if (!asesor) {
          UI.showToast('Selecciona un docente asesor para guardar el dictamen.', 'warning');
          return;
        }
        await Store.academiaAsignarAsesor(idVal, {
          asesorInterno: asesor,
          folioAcademia: folioAcad,
          dictamen,
          autoOficioPB: false
        });
        UI.showToast('Dictamen y asesor de Academia guardados', 'success');
        navigateTo('academia', 'bandeja');
      } catch (err) {
        UI.showToast(err.message, 'error');
      }
      return;
    }

    const ssRadio = document.querySelector('input[name="f-ss-radio"]:checked')?.value || 'Por verificar';
    const payload = {
      id: idVal ? Number(idVal) : null,
      control: document.getElementById('f-control').value.trim(),
      nombre: document.getElementById('f-nombre').value.trim(),
      correoInstitucional: (document.getElementById('f-correo')?.value || '').trim().toLowerCase(),
      semestre: document.getElementById('f-semestre').value,
      especialidad: document.getElementById('f-especialidad').value.trim(),
      servicioSocial: ssRadio,
      estado: document.getElementById('f-estado').value,
      proyecto: document.getElementById('f-proyecto').value.trim(),
      empresa: document.getElementById('f-empresa').value.trim(),
      asesorExterno: document.getElementById('f-asesor-ext').value.trim(),
      horario: document.getElementById('f-horario').value.trim(),
      periodo: document.getElementById('f-periodo').value.trim(),
      fechaEntregaFisica: document.getElementById('f-fecha-fisica').value,
      fechaEntregaAcademia: document.getElementById('f-fecha-academia').value,
      oficioAutorizacion: document.getElementById('f-oficio-aut').value.trim(),
      fechaImpresion: document.getElementById('f-fecha-imp').value,
      notificadoAlumno: document.getElementById('f-notificado').value,
      fechaEnvioAutCorreo: document.getElementById('f-fecha-aut-correo').value,
      observaciones: document.getElementById('f-observaciones').value.trim(),
      actualizarAcademia: appState.academiaEditUnlocked,
      revisadoAcademia: document.getElementById('f-revisado-acad').value,
      asesorInterno: document.getElementById('f-asesor-int').value.trim(),
      folioAcademia: document.getElementById('f-folio-acad').value.trim(),
      oficioAsesorInterno: document.getElementById('f-oficio-asesor').value.trim(),
      fechaEnvioAsesorCorreo: document.getElementById('f-fecha-asesor-correo').value
    };

    try {
      const saved = await Store.registrarOSalvarExpediente(payload);
      UI.showToast(`Expediente #${saved.id} guardado`, 'success');
      navigateTo('expedientes');
    } catch (err) {
      UI.showToast(err.message, 'error');
    }
  }

  // =========================================================================
  // VISTA 3: MESA DE EMISIÓN DE OFICIOS (TABLA FINDER LIMPIA SIN RECORTES)
  // =========================================================================
  function renderOficiosView() {
    const all = Store.getResidencias().filter((r) => r.proyecto);
    const pendientes = all.filter(Store.isPendingGestionOficio);
    const emitidos = all.filter((r) => r.oficioAutorizacion && r.oficioAsesorInterno);

    const sinPA = pendientes.filter((r) => !r.oficioAutorizacion).length;
    const sinPB = pendientes.filter((r) => !r.oficioAsesorInterno).length;
    const sinNotif = pendientes.filter((r) => !r.notificadoAlumno).length;

    const kpiEl = document.getElementById('oficios-kpis');
    if (kpiEl) {
      kpiEl.innerHTML = `
        <div class="mac-card p-3.5">
          <div class="flex items-center justify-between"><span class="text-[11.5px] font-medium text-[#6e6e73]">Pendientes Oficio Aut. (P.A)</span><span class="w-2 h-2 rounded-full bg-[#ff9500]"></span></div>
          <div class="text-[22px] font-semibold num-tabular text-[#1d1d1f] mt-0.5">${sinPA}</div>
          <div class="text-[11px] text-[#86868b]">Siguiente: <span class="num-tabular font-semibold text-[#1d1d1f]">${Store.getNextFolio('PA', 2026)}</span></div>
        </div>
        <div class="mac-card p-3.5">
          <div class="flex items-center justify-between"><span class="text-[11.5px] font-medium text-[#6e6e73]">Pendientes Oficio Asesor (P.B)</span><span class="w-2 h-2 rounded-full bg-[#007aff]"></span></div>
          <div class="text-[22px] font-semibold num-tabular text-[#1d1d1f] mt-0.5">${sinPB}</div>
          <div class="text-[11px] text-[#86868b]">Siguiente: <span class="num-tabular font-semibold text-[#1d1d1f]">${Store.getNextFolio('PB', 2026)}</span></div>
        </div>
        <div class="mac-card p-3.5">
          <div class="flex items-center justify-between"><span class="text-[11.5px] font-medium text-[#6e6e73]">Sin Notificar Recoger</span><span class="w-2 h-2 rounded-full bg-[#5856d6]"></span></div>
          <div class="text-[22px] font-semibold num-tabular text-[#1d1d1f] mt-0.5">${sinNotif}</div>
          <div class="text-[11px] text-[#86868b]">Avisos pendientes al alumno</div>
        </div>
        <div class="mac-card p-3.5">
          <div class="flex items-center justify-between"><span class="text-[11.5px] font-medium text-[#6e6e73]">Con Ambos Oficios</span><span class="w-2 h-2 rounded-full bg-[#34c759]"></span></div>
          <div class="text-[22px] font-semibold num-tabular text-[#1d1d1f] mt-0.5">${emitidos.length}</div>
          <div class="text-[11px] text-[#86868b]">P.A y P.B completados</div>
        </div>
      `;
    }

    document.querySelectorAll('[data-oficios-subtab]').forEach((btn) => {
      btn.classList.toggle('is-active', btn.dataset.oficiosSubtab === appState.oficiosSubtab);
    });

    const list = appState.oficiosSubtab === 'emitidos' ? emitidos.slice(0, 60) : pendientes;
    const tbody = document.getElementById('oficios-tbody');
    if (!tbody) return;

    if (list.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="py-10 text-center text-xs text-[#6e6e73]">No hay expedientes en esta bandeja de oficios.</td></tr>';
      return;
    }

    tbody.innerHTML = list.map((r) => `
      <tr class="hover:bg-[#007aff]/[0.035] transition">
        <td class="whitespace-nowrap">
          <div class="font-semibold text-[#1d1d1f]">${UI.escapeHtml(UI.formatPersonName(r.nombre))}</div>
          <div class="num-tabular text-[11px] text-[#6e6e73] mt-0.5 flex items-center gap-1.5">
            <span>${UI.escapeHtml(r.control)}</span>
            <span>·</span>
            ${UI.renderSSBadge(r.servicioSocial, true)}
          </div>
        </td>
        <td>
          <div class="font-medium text-[#1d1d1f] line-clamp-2 max-w-sm leading-snug">${UI.escapeHtml(UI.formatTitleText(r.proyecto))}</div>
          <div class="text-[11px] text-[#6e6e73] mt-0.5">${UI.escapeHtml(UI.formatTitleText(r.empresa || 'Sin empresa'))}</div>
        </td>
        <td class="whitespace-nowrap">
          ${r.oficioAutorizacion
            ? `<span class="num-tabular font-semibold text-[#1b7a34]">${UI.escapeHtml(r.oficioAutorizacion)}</span>`
            : `<button type="button" data-action="emitir-pa" data-id="${r.id}" class="mac-btn-primary py-1 min-h-[26px] text-[11px]">Emitir P.A</button>`}
        </td>
        <td>
          <div class="font-medium text-[#1d1d1f] text-[12px]">${UI.escapeHtml(r.asesorInterno ? UI.formatPersonName(r.asesorInterno) : 'Sin asignar')}</div>
          <div class="mt-0.5">
            ${r.oficioAsesorInterno
              ? `<span class="num-tabular text-[11px] font-medium text-[#1b7a34]">${UI.escapeHtml(r.oficioAsesorInterno)}</span>`
              : `<button type="button" data-action="emitir-pb" data-id="${r.id}" class="mac-btn-primary is-academia py-0.5 min-h-[24px] text-[11px] px-2">Emitir P.B</button>`}
          </div>
        </td>
        <td class="whitespace-nowrap">
          ${r.notificadoAlumno
            ? `<div class="num-tabular text-[11.5px] text-[#1b7a34] font-medium">${UI.formatDateShort(r.notificadoAlumno)}</div>
               <div class="text-[10.5px] text-[#6e6e73]">${UI.escapeHtml(r.medioNotificacion || 'Avisado')}</div>`
            : `<button type="button" data-action="open-outlook-modal" data-id="${r.id}" class="mac-btn-primary py-1 min-h-[26px] text-[11px]" style="background:#0078d4;">
                 <span class="material-symbols-outlined text-[13px]">mail</span>
                 <span>Avisar Outlook</span>
               </button>`}
        </td>
        <td class="text-right whitespace-nowrap">
          <div class="inline-flex items-center gap-1.5">
            <button type="button" data-action="preview-oficio" data-id="${r.id}" title="Vista previa e impresión" class="mac-btn-secondary w-8 h-7 p-0 min-h-[28px]">
              <span class="material-symbols-outlined text-[15px] text-[#007aff]">print</span>
            </button>
            <button type="button" data-action="open-detail" data-id="${r.id}" class="mac-btn-secondary py-1 min-h-[28px] text-[11px]">
              Ver
            </button>
          </div>
        </td>
      </tr>
    `).join('');
  }

  // =========================================================================
  // VISTA 4: ACADEMIA · BANDEJA DE ASIGNACIÓN Y MATRIZ DE 42 DOCENTES
  // =========================================================================
  function renderAcademiaView() {
    const kpis = Store.getKPIs();
    const maestros = Store.getMaestros();
    const bajaCarga = maestros.filter((m) => Store.countActiveForTeacher(m.nombre) <= 1).length;

    const kpiEl = document.getElementById('academia-kpis');
    if (kpiEl) {
      kpiEl.innerHTML = `
        <div class="mac-card p-3.5">
          <div class="flex items-center justify-between"><span class="text-[11.5px] font-medium text-[#6e6e73]">Sin Asesor Interno</span><span class="w-2 h-2 rounded-full bg-[#ff3b30]"></span></div>
          <div class="text-[22px] font-semibold num-tabular text-[#1d1d1f] mt-0.5">${kpis.sinAsesor}</div>
          <div class="text-[11px] text-[#86868b]">Requieren asignación inmediata</div>
        </div>
        <div class="mac-card p-3.5">
          <div class="flex items-center justify-between"><span class="text-[11.5px] font-medium text-[#6e6e73]">Con Asesor · Falta Oficio P.B</span><span class="w-2 h-2 rounded-full bg-[#5856d6]"></span></div>
          <div class="text-[22px] font-semibold num-tabular text-[#1d1d1f] mt-0.5">${Math.max(0, kpis.pendientesAcademia - kpis.sinAsesor)}</div>
          <div class="text-[11px] text-[#86868b]">En espera de oficio P.B</div>
        </div>
        <div class="mac-card p-3.5">
          <div class="flex items-center justify-between"><span class="text-[11.5px] font-medium text-[#6e6e73]">Docentes Disponibles (≤1)</span><span class="w-2 h-2 rounded-full bg-[#34c759]"></span></div>
          <div class="text-[22px] font-semibold num-tabular text-[#1d1d1f] mt-0.5">${bajaCarga}</div>
          <div class="text-[11px] text-[#86868b]">Con menor carga actual</div>
        </div>
        <div class="mac-card p-3.5">
          <div class="flex items-center justify-between"><span class="text-[11.5px] font-medium text-[#6e6e73]">Plantilla Docente</span><span class="w-2 h-2 rounded-full bg-[#007aff]"></span></div>
          <div class="text-[22px] font-semibold num-tabular text-[#1d1d1f] mt-0.5">${maestros.length}</div>
          <div class="text-[11px] text-[#86868b]">De hoja Maestros oficial</div>
        </div>
      `;
    }

    document.querySelectorAll('[data-academia-subtab]').forEach((btn) => {
      btn.classList.toggle('is-active', btn.dataset.academiaSubtab === appState.academiaSubtab);
    });

    const bandejaPanel = document.getElementById('academia-subpanel-bandeja');
    const docentesPanel = document.getElementById('academia-subpanel-docentes');
    if (bandejaPanel) bandejaPanel.hidden = appState.academiaSubtab !== 'bandeja';
    if (docentesPanel) docentesPanel.hidden = appState.academiaSubtab !== 'docentes';

    if (appState.academiaSubtab === 'bandeja') {
      renderAcademiaPendingList();
    } else {
      renderMaestrosMatrix();
    }
  }

  function renderAcademiaPendingList() {
    const pending = Store.getResidencias().filter(Store.isPendingAcademia);
    const listEl = document.getElementById('academia-pending-list');
    if (!listEl) return;

    if (pending.length === 0) {
      listEl.innerHTML = `
        <div class="p-10 text-center">
          <span class="material-symbols-outlined text-4xl text-[#34c759]">task_alt</span>
          <div class="text-sm font-semibold text-[#1d1d1f] mt-2">Bandeja al día</div>
          <p class="text-xs text-[#6e6e73] mt-0.5">Todos los anteproyectos entregados cuentan con Asesor Interno y Oficio P.B.</p>
        </div>
      `;
      return;
    }

    const sortedTeachers = Store.getMaestros().slice().sort((a, b) => {
      return Store.countActiveForTeacher(a.nombre) - Store.countActiveForTeacher(b.nombre);
    });

    const teacherOptionsHtml = sortedTeachers.map((m) => {
      const cnt = Store.countActiveForTeacher(m.nombre);
      const edd = m.beca === 'EDD' ? ' · EDD' : '';
      return `<option value="${UI.escapeHtml(m.nombre.toUpperCase())}">${UI.escapeHtml(UI.formatPersonName(m.nombre))} — ${cnt} act. (${UI.escapeHtml(m.jornada)}${edd})</option>`;
    }).join('');

    listEl.innerHTML = pending.map((r) => {
      const ssWarn = r.servicioSocial !== 'Liberado'
        ? `<div class="mt-2 px-3 py-1.5 rounded-lg text-[11px] flex items-center gap-1.5" style="background: rgba(255, 149, 0, 0.10); color: #b25000;">
             <span class="material-symbols-outlined text-[15px]">warning</span>
             <span><b>Aviso Servicio Social:</b> Estatus "${UI.escapeHtml(r.servicioSocial)}".</span>
           </div>`
        : '';

      return `
        <article class="p-4 sm:p-5 flex flex-col xl:flex-row xl:items-center justify-between gap-4 hover:bg-[#5856d6]/[0.03] transition">
          <div class="space-y-1 flex-1 min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <span class="num-tabular text-xs font-semibold text-[#5856d6]">${UI.escapeHtml(r.control)}</span>
              <span class="text-[13px] font-semibold text-[#1d1d1f]">${UI.escapeHtml(UI.formatPersonName(r.nombre))}</span>
              ${UI.renderStatusBadge(r.estado)}
              ${UI.renderSSBadge(r.servicioSocial, true)}
            </div>
            <div class="text-xs font-medium text-[#1d1d1f] leading-snug">${UI.escapeHtml(UI.formatTitleText(r.proyecto))}</div>
            <div class="text-[11px] text-[#6e6e73] flex flex-wrap items-center gap-3">
              <span>Empresa: <b class="text-[#1d1d1f] font-medium">${UI.escapeHtml(UI.formatTitleText(r.empresa || 'Por definir'))}</b></span>
              <span>Oficio Aut.: <b class="num-tabular text-[#1d1d1f]">${UI.escapeHtml(r.oficioAutorizacion || 'Sin P.A')}</b></span>
              <span>Asesor actual: <b class="${r.asesorInterno ? 'text-[#1d1d1f]' : 'text-[#c92a2a]'}">${UI.escapeHtml(r.asesorInterno ? UI.formatPersonName(r.asesorInterno) : 'Sin asignar')}</b></span>
            </div>
            ${ssWarn}
          </div>

          <div class="flex flex-wrap sm:flex-nowrap items-center gap-2 shrink-0">
            <select id="acad-select-${r.id}" class="mac-select py-1.5 px-2.5 max-w-[260px]">
              <option value="">-- Elegir Docente (menor carga) --</option>
              ${teacherOptionsHtml}
            </select>
            <input type="text" id="acad-folio-${r.id}" value="${UI.escapeHtml(r.folioAcademia || '26-1-1')}"
              placeholder="26-1-1" class="mac-input num-tabular w-20 py-1.5 px-2 text-center" title="Folio Control Academia">
            <button type="button" data-action="acad-assign" data-id="${r.id}" class="mac-btn-primary is-academia">
              Aprobar y Asignar
            </button>
            <button type="button" data-action="open-detail" data-id="${r.id}" class="mac-btn-secondary">
              Ver
            </button>
          </div>
        </article>
      `;
    }).join('');
  }

  function renderMaestrosMatrix() {
    const normQ = Store.normalizeText(appState.maestrosFilter.q);
    const jFilter = appState.maestrosFilter.jornada;
    const bFilter = appState.maestrosFilter.beca;

    const filtered = Store.getMaestros().filter((m) => {
      if (jFilter !== 'ALL' && m.jornada !== jFilter) return false;
      if (bFilter === 'EDD' && m.beca !== 'EDD') return false;
      if (bFilter === 'SIN_BECA' && m.beca === 'EDD') return false;
      if (normQ) {
        const hay = Store.normalizeText(`${m.nombre} ${m.jornada} ${m.beca}`);
        if (!hay.includes(normQ)) return false;
      }
      return true;
    });

    const tbody = document.getElementById('maestros-tbody');
    if (!tbody) return;

    tbody.innerHTML = filtered.map((m) => {
      const active = Store.countActiveForTeacher(m.nombre);
      return `
        <tr class="hover:bg-[#007aff]/[0.035] transition">
          <td class="num-tabular text-[#6e6e73]">#${m.id}</td>
          <td class="font-semibold text-[#1d1d1f]">${UI.escapeHtml(UI.formatPersonName(m.nombre))}</td>
          <td><span class="num-tabular text-[11px] px-2 py-0.5 rounded-md bg-black/[0.05] text-[#1d1d1f]">${UI.escapeHtml(m.jornada)}</span></td>
          <td>
            ${m.beca === 'EDD'
              ? '<span class="px-2 py-0.5 rounded-full text-[10px] font-semibold" style="background: rgba(255, 149, 0, 0.14); color: #b25000;">EDD</span>'
              : '<span class="text-[#86868b] text-[11px]">—</span>'}
          </td>
          <td class="text-center num-tabular text-[#1d1d1f]">${m.proyectosEneJun} <span class="text-[10.5px] text-[#86868b]">(Int:${m.proyectoInternoEneJun})</span></td>
          <td class="text-center num-tabular text-[#1d1d1f]">${m.proyectosAgoDic} <span class="text-[10.5px] text-[#86868b]">(Int:${m.proyectoInternoAgoDic})</span></td>
          <td>${UI.renderTeacherLoadBar(active, m.jornada)}</td>
          <td class="text-right whitespace-nowrap">
            <button type="button" data-action="filter-by-teacher" data-teacher="${UI.escapeHtml(m.nombre)}" class="mac-btn-secondary">
              Ver residentes (${active})
            </button>
          </td>
        </tr>
      `;
    }).join('');
  }

  // =========================================================================
  // VISTA 5: TRÁMITES PAUSADOS Y ALERTAS DE SERVICIO SOCIAL
  // =========================================================================
  function renderExcepcionesView() {
    const all = Store.getResidencias();
    const pausados = all.filter((r) => r.estado === 'Pausado / Sin Oficio' || r.estado === 'Caso Especial / Reasignación');
    const alertasSS = all.filter((r) => r.servicioSocial !== 'Liberado');

    const bPau = document.getElementById('exc-badge-pausados');
    const bSS = document.getElementById('exc-badge-ss');
    if (bPau) bPau.textContent = pausados.length;
    if (bSS) bSS.textContent = alertasSS.length;

    if (appState.excepcionesSubtab !== 'pausados' && appState.excepcionesSubtab !== 'ss') {
      appState.excepcionesSubtab = 'pausados';
    }

    document.querySelectorAll('[data-exc-subtab]').forEach((btn) => {
      btn.classList.toggle('is-active', btn.dataset.excSubtab === appState.excepcionesSubtab);
    });

    const listEl = document.getElementById('excepciones-list');
    if (!listEl) return;

    const searchQ = Store.normalizeText(document.getElementById('exc-search')?.value || '');
    const filterBySearch = (arr) => {
      if (!searchQ) return arr;
      return arr.filter((r) => Store.normalizeText(`${r.control} ${r.nombre} ${r.proyecto} ${r.observaciones}`).includes(searchQ));
    };

    if (appState.excepcionesSubtab === 'pausados') {
      const items = filterBySearch(pausados);
      listEl.innerHTML = items.length === 0
        ? '<div class="p-8 text-center text-xs text-[#6e6e73]">No hay trámites pausados o reasignaciones.</div>'
        : items.map((r) => `
          <article class="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-[#007aff]/[0.03] transition">
            <div class="space-y-1 max-w-2xl">
              <div class="flex flex-wrap items-center gap-2">
                <span class="num-tabular text-xs font-semibold text-[#1d1d1f]">${UI.escapeHtml(r.control)}</span>
                <span class="text-[13px] font-semibold text-[#1d1d1f]">${UI.escapeHtml(UI.formatPersonName(r.nombre))}</span>
                ${UI.renderStatusBadge(r.estado)}
                ${UI.renderSSBadge(r.servicioSocial, true)}
              </div>
              <p class="text-xs font-medium text-[#1d1d1f]">${UI.escapeHtml(UI.formatTitleText(r.proyecto || 'Sin título'))}</p>
              <p class="text-[11px] text-[#6e6e73]">${UI.escapeHtml(r.observaciones || 'Trámite detenido sin concluir oficios')}</p>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <button type="button" data-action="reactivar-tramite" data-id="${r.id}"
                class="px-3 py-1.5 rounded-lg text-white text-xs font-semibold transition" style="background: #1b7a34;">
                Reactivar Trámite
              </button>
              <button type="button" data-action="open-detail" data-id="${r.id}" class="mac-btn-secondary">
                Ver Expediente
              </button>
            </div>
          </article>
        `).join('');
      return;
    }

    const items = filterBySearch(alertasSS);
    listEl.innerHTML = items.length === 0
      ? '<div class="p-8 text-center text-xs text-[#6e6e73]">Todos los alumnos tienen Servicio Social Liberado.</div>'
      : items.map((r) => `
        <article class="p-4 flex flex-col lg:flex-row lg:items-center justify-between gap-3 hover:bg-[#007aff]/[0.03] transition">
          <div class="space-y-1 max-w-2xl">
            <div class="flex flex-wrap items-center gap-2">
              <span class="num-tabular text-xs font-semibold text-[#1d1d1f]">${UI.escapeHtml(r.control)}</span>
              <span class="text-[13px] font-semibold text-[#1d1d1f]">${UI.escapeHtml(UI.formatPersonName(r.nombre))}</span>
              ${UI.renderSSBadge(r.servicioSocial)}
              ${UI.renderStatusBadge(r.estado)}
            </div>
            <p class="text-[11.5px] text-[#6e6e73]">${UI.escapeHtml(UI.formatTitleText(r.proyecto || 'Sin título de anteproyecto'))}</p>
          </div>
          <div class="flex flex-wrap items-center gap-2 shrink-0">
            <button type="button" data-action="ss-confirm-ok" data-id="${r.id}"
              class="px-3 py-1.5 rounded-lg text-white text-xs font-semibold transition" style="background: #1b7a34;">
              Confirmar S.S. Liberado ✓
            </button>
            <button type="button" data-action="ss-block" data-id="${r.id}"
              class="px-3 py-1.5 rounded-lg text-white text-xs font-semibold transition" style="background: #c92a2a;">
              Bloquear por Falta de S.S.
            </button>
          </div>
        </article>
      `).join('');
  }

  // =========================================================================
  // VISTA 6: BITÁCORA AUDITABLE DE MOVIMIENTOS
  // =========================================================================
  function renderBitacoraView() {
    const q = Store.normalizeText(appState.bitacoraFilter.q);
    const u = appState.bitacoraFilter.usuario;

    const list = Store.getBitacora().filter((b) => {
      if (u !== 'ALL' && b.usuario !== u) return false;
      if (q) {
        const hay = Store.normalizeText(`${b.control} ${b.nombreAlumno} ${b.operacion} ${b.descripcion} ${b.estadoNuevo}`);
        if (!hay.includes(q)) return false;
      }
      return true;
    });

    const tbody = document.getElementById('bitacora-tbody');
    if (!tbody) return;

    if (list.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="py-10 text-center text-xs text-[#6e6e73]">No hay movimientos registrados con ese filtro.</td></tr>';
      return;
    }

    tbody.innerHTML = list.map((b) => {
      let pillStyle = 'background: rgba(118,118,128,0.12); color:#6e6e73;';
      if (b.usuario === 'ACADEMIA') pillStyle = 'background: rgba(88,86,214,0.12); color:#4b49b6;';
      else if (b.usuario !== 'SISTEMA') pillStyle = 'background: rgba(0,122,255,0.12); color:#0066cc;';

      return `
        <tr class="hover:bg-[#007aff]/[0.03] transition">
          <td class="num-tabular text-[11.5px] text-[#6e6e73] whitespace-nowrap">${UI.formatDateTimeShort(b.fecha)}</td>
          <td>
            <span class="px-2 py-0.5 rounded-full text-[10.5px] font-semibold" style="${pillStyle}">${UI.escapeHtml(b.usuario)}</span>
          </td>
          <td class="num-tabular text-[11.5px] font-medium text-[#1d1d1f]">${UI.escapeHtml(b.operacion)}</td>
          <td>
            <div class="num-tabular text-[11.5px] font-semibold text-[#007aff]">${UI.escapeHtml(b.control)}</div>
            <div class="text-xs font-medium text-[#1d1d1f]">${UI.escapeHtml(UI.formatPersonName(b.nombreAlumno))}</div>
          </td>
          <td class="text-[11.5px]">
            <span class="text-[#86868b]">${UI.escapeHtml(b.estadoAnterior)}</span>
            <span class="mx-1 text-[#aeaeb2]">→</span>
            <span class="font-semibold text-[#1d1d1f]">${UI.escapeHtml(b.estadoNuevo)}</span>
          </td>
          <td class="text-xs text-[#6e6e73] max-w-md">${UI.escapeHtml(b.descripcion)}</td>
        </tr>
      `;
    }).join('');
  }

  // =========================================================================
  // SLIDE-OVER SHEET DRAWER DERECHO (STYLE MACOS SYSTEM SETTINGS)
  // =========================================================================
  function openDetailDrawer(id) {
    const r = Store.getById(id);
    if (!r) return;
    appState.selectedId = r.id;

    const roleMeta = Store.getRoleMeta();
    const isAcademia = roleMeta.isAcademia;

    const headerMeta = document.getElementById('drawer-meta');
    const headerTitle = document.getElementById('drawer-title');
    const bodyEl = document.getElementById('drawer-body');
    const footerEl = document.getElementById('drawer-footer');

    if (headerMeta) headerMeta.textContent = `Expediente #${r.id} · Control ${r.control} · ${r.semestre}`;
    if (headerTitle) headerTitle.textContent = UI.formatPersonName(r.nombre);

    const sortedTeachers = Store.getMaestros().slice().sort((a, b) =>
      Store.countActiveForTeacher(a.nombre) - Store.countActiveForTeacher(b.nombre)
    );
    const teacherOpts = sortedTeachers.map((m) => {
      const cnt = Store.countActiveForTeacher(m.nombre);
      const selected = Store.normalizeText(r.asesorInterno).includes(Store.normalizeText(m.nombre.split(' ')[0])) ? 'selected' : '';
      return `<option value="${UI.escapeHtml(m.nombre.toUpperCase())}" ${selected}>${UI.escapeHtml(UI.formatPersonName(m.nombre))} (${cnt} activos · ${UI.escapeHtml(m.jornada)})</option>`;
    }).join('');

    if (bodyEl) {
      bodyEl.innerHTML = `
        <div class="flex flex-wrap items-center gap-1.5">
          ${UI.renderStatusBadge(r.estado)}
          ${UI.renderSSBadge(r.servicioSocial)}
          <span class="px-2 py-0.5 rounded-full bg-black/[0.06] text-[#1d1d1f] text-[10.5px] font-medium">${UI.escapeHtml(UI.formatTitleText(r.especialidad))}</span>
        </div>

        ${UI.renderFullStepper(r)}

        <!-- Bloque Agrupado: Proyecto y Empresa -->
        <div class="space-y-1.5">
          <div class="text-[11px] font-semibold uppercase tracking-wider text-[#6e6e73] px-1">Proyecto y Empresa</div>
          <div class="mac-group">
            <div class="p-3.5 border-b border-black/[0.06]">
              <div class="text-[11px] text-[#86868b] mb-0.5">Anteproyecto</div>
              <div class="text-[12.5px] font-semibold text-[#1d1d1f] leading-relaxed">${UI.escapeHtml(r.proyecto ? UI.formatTitleText(r.proyecto) : 'No ha entregado hojas de anteproyecto')}</div>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Correo Institucional</span>
              <span class="text-[#0078d4] font-medium text-right">${UI.escapeHtml(r.correoInstitucional || 'Sin correo')}</span>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Empresa Receptora</span>
              <span class="font-medium text-[#1d1d1f] text-right">${UI.escapeHtml(r.empresa ? UI.formatTitleText(r.empresa) : '—')}</span>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Asesor Externo</span>
              <span class="font-medium text-[#1d1d1f] text-right">${UI.escapeHtml(r.asesorExterno ? UI.formatPersonName(r.asesorExterno) : '—')}</span>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Horario</span>
              <span class="num-tabular text-[#1d1d1f] text-right">${UI.escapeHtml(r.horario ? UI.formatTitleText(r.horario) : '—')}</span>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Período de Realización</span>
              <span class="num-tabular text-[#1d1d1f] text-right">${UI.escapeHtml(r.periodo ? UI.formatTitleText(r.periodo) : '—')}</span>
            </div>
          </div>
        </div>

        <!-- Bloque Agrupado: Oficina de Gestión -->
        <div class="space-y-1.5">
          <div class="flex items-center justify-between px-1">
            <span class="text-[11px] font-semibold uppercase tracking-wider text-[#6e6e73]">Oficina de Gestión · Recepción y Oficios</span>
            ${isAcademia ? '<span class="inline-flex items-center gap-1 text-[10.5px] font-medium text-[#6e6e73]"><span class="material-symbols-outlined text-[12px]">lock</span>Solo lectura</span>' : ''}
          </div>
          <div class="mac-group">
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Entrega Física / A Academia</span>
              <span class="num-tabular text-[#1d1d1f]">${UI.formatDateShort(r.fechaEntregaFisica)} · ${UI.formatDateShort(r.fechaEntregaAcademia)}</span>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Oficio Autorización (P.A)</span>
              <span class="num-tabular font-semibold text-[#007aff]">${UI.escapeHtml(r.oficioAutorizacion || 'Pendiente')}</span>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Impresión / Aviso Outlook</span>
              <span class="num-tabular text-[#1d1d1f]">${UI.formatDateShort(r.fechaImpresion)} · ${r.notificadoAlumno ? `${UI.formatDateShort(r.notificadoAlumno)} (${UI.escapeHtml(r.medioNotificacion || 'Avisado')})` : 'Pendiente'}</span>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Oficio Asesor Interno (P.B)</span>
              <span class="num-tabular font-semibold text-[#007aff]">${UI.escapeHtml(r.oficioAsesorInterno || 'Pendiente')}</span>
            </div>
            ${!isAcademia && r.proyecto ? `
              <div class="p-3 bg-[#fafafc] flex flex-wrap gap-2">
                ${!r.oficioAutorizacion ? `
                  <button type="button" data-action="emitir-pa" data-id="${r.id}" class="mac-btn-primary">
                    Aceptar y Emitir P.A Auto
                  </button>` : ''}
                ${!r.oficioAsesorInterno ? `
                  <button type="button" data-action="emitir-pb" data-id="${r.id}" class="mac-btn-primary is-academia">
                    Emitir Oficio P.B
                  </button>` : ''}
                <button type="button" data-action="open-outlook-modal" data-id="${r.id}" class="mac-btn-primary" style="background:#0078d4;">
                  <span class="material-symbols-outlined text-[14px]">mail</span>
                  <span>${r.notificadoAlumno ? 'Reenviar Aviso Outlook' : 'Avisar por Outlook'}</span>
                </button>
                <button type="button" data-action="preview-oficio" data-id="${r.id}" class="mac-btn-secondary">
                  <span class="material-symbols-outlined text-[14px] text-[#007aff]">print</span> Vista Previa Oficio
                </button>
              </div>
            ` : ''}
          </div>
        </div>

        <!-- Bloque Agrupado: Academia -->
        <div class="space-y-1.5">
          <div class="flex items-center justify-between px-1">
            <span class="text-[11px] font-semibold uppercase tracking-wider text-[#6e6e73]">Academia · Dictamen y Asesor Interno</span>
            ${isAcademia ? '<span class="text-[10.5px] font-semibold text-[#5856d6]">Tu sección editable</span>' : '<span class="text-[10.5px] text-[#86868b]">Responsabilidad de Academia</span>'}
          </div>
          <div class="mac-group ${isAcademia ? 'ring-2 ring-[#5856d6]/25' : ''}">
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Dictamen / Folio Academia</span>
              <span class="font-medium text-[#1d1d1f]">${UI.escapeHtml(r.revisadoAcademia)} · <span class="num-tabular">${UI.escapeHtml(r.folioAcademia || '—')}</span></span>
            </div>
            <div class="mac-group-row">
              <span class="text-[#6e6e73]">Asesor Interno</span>
              <span class="font-semibold text-[#1d1d1f] text-right">${UI.escapeHtml(r.asesorInterno ? UI.formatPersonName(r.asesorInterno) : 'Sin asignar')}</span>
            </div>
            ${r.proyecto && (isAcademia || !r.asesorInterno) ? `
              <div class="p-3 bg-[#fafafc] space-y-2">
                <label class="block text-[11px] font-semibold text-[#6e6e73]">Asignar o cambiar Asesor Interno</label>
                <div class="flex flex-col sm:flex-row gap-2">
                  <select id="drawer-asesor-select" class="mac-select flex-1 py-1.5 px-2.5">
                    <option value="">-- Seleccionar Docente --</option>
                    ${teacherOpts}
                  </select>
                  <input type="text" id="drawer-folio-input" value="${UI.escapeHtml(r.folioAcademia || '26-1-1')}" class="mac-input num-tabular w-24 py-1.5 px-2 text-center">
                  <button type="button" data-action="drawer-assign-asesor" data-id="${r.id}" class="mac-btn-primary is-academia">
                    Guardar Asesor
                  </button>
                </div>
              </div>
            ` : ''}
          </div>
        </div>

        <!-- Observaciones -->
        <div class="mac-group">
          <div class="p-3.5 text-xs">
            <div class="text-[11px] text-[#86868b] mb-0.5">Observaciones</div>
            <div class="text-[#1d1d1f]">${UI.escapeHtml(r.observaciones || 'Sin observaciones registradas.')}</div>
          </div>
        </div>
      `;
    }

    if (footerEl) {
      footerEl.innerHTML = `
        <div class="flex flex-wrap items-center gap-2">
          ${!isAcademia ? `
            <button type="button" data-action="drawer-toggle-pause" data-id="${r.id}" class="mac-btn-secondary">
              ${r.estado === 'Pausado / Sin Oficio' ? 'Reactivar Trámite' : 'Marcar Pausado'}
            </button>
            <button type="button" data-action="drawer-cycle-ss" data-id="${r.id}" class="mac-btn-secondary">
              Cambiar S.S.
            </button>
          ` : ''}
        </div>
        <button type="button" data-action="edit-in-form" data-id="${r.id}"
          class="mac-btn-primary ${isAcademia ? 'is-academia' : ''}">
          <span class="material-symbols-outlined text-[15px]">edit</span>
          <span>${isAcademia ? 'Abrir Dictamen Completo' : 'Editar en Formulario'}</span>
        </button>
      `;
    }

    document.body.classList.add('detail-open');
  }

  function closeDetailDrawer() {
    document.body.classList.remove('detail-open');
    appState.selectedId = null;
  }

  // =========================================================================
  // MODAL DE VISTA PREVIA DE OFICIO IMPRIMIBLE
  // =========================================================================
  function openOficioModal(id) {
    const r = Store.getById(id);
    if (!r) return;

    const modal = document.getElementById('oficio-modal');
    const area = document.getElementById('oficio-print-area');
    if (!modal || !area) return;

    const pa = r.oficioAutorizacion || Store.getNextFolio('PA', 2026);
    const pb = r.oficioAsesorInterno || Store.getNextFolio('PB', 2026);

    area.innerHTML = `
    
      <div class="space-y-6 text-[#1d1d1f] text-xs leading-relaxed">
        <div class="flex items-start justify-between border-b-2 border-[#1d1d1f] pb-4">
          <div>
            <div class="text-[11px] font-semibold uppercase tracking-widest text-[#6e6e73]">Tecnológico Nacional de México</div>
            <div class="text-sm font-bold text-[#1d1d1f]">Departamento de Ingeniería Industrial</div>
            <div class="text-[11px] text-[#6e6e73]">Coordinación de Residencias Profesionales · Gestión y Academia</div>
          </div>
          <div class="text-right num-tabular text-[11px]">
            <div><b>Oficio Aut.:</b> ${UI.escapeHtml(pa)}</div>
            <div><b>Oficio Asesor:</b> ${UI.escapeHtml(pb)}</div>
            <div><b>Fecha:</b> ${UI.formatDateShort(Store.todayISO())}</div>
          </div>
        </div>

        <div class="text-center py-2">
          <div class="text-sm font-bold uppercase tracking-wide text-[#1d1d1f]">Constancia de Autorización y Asignación de Asesor Interno</div>
          <div class="text-[11px] num-tabular text-[#6e6e73] mt-0.5">Semestre: ${UI.escapeHtml(r.semestre)} · Especialidad: ${UI.escapeHtml(UI.formatTitleText(r.especialidad))}</div>
        </div>

        <div class="border border-black/15 rounded-xl p-4 space-y-2.5 bg-[#fafafc]">
          <div class="grid grid-cols-3 gap-2">
            <div><span class="text-[#6e6e73]">N° de Control:</span><br><b class="num-tabular text-sm">${UI.escapeHtml(r.control)}</b></div>
            <div class="col-span-2"><span class="text-[#6e6e73]">Estudiante Residente:</span><br><b class="text-sm">${UI.escapeHtml(UI.formatPersonName(r.nombre))}</b></div>
          </div>
          <div>
            <span class="text-[#6e6e73]">Nombre del Proyecto Autorizado:</span><br>
            <b class="text-xs">${UI.escapeHtml(r.proyecto ? UI.formatTitleText(r.proyecto) : 'SIN PROYECTO')}</b>
          </div>
          <div class="grid grid-cols-2 gap-2 pt-2 border-t border-black/10">
            <div><span class="text-[#6e6e73]">Empresa Receptora:</span><br><b>${UI.escapeHtml(r.empresa ? UI.formatTitleText(r.empresa) : '—')}</b></div>
            <div><span class="text-[#6e6e73]">Período y Horario:</span><br><b class="num-tabular">${UI.escapeHtml(r.periodo ? UI.formatTitleText(r.periodo) : '—')} · ${UI.escapeHtml(r.horario ? UI.formatTitleText(r.horario) : '')}</b></div>
            <div><span class="text-[#6e6e73]">Asesor Interno (Academia):</span><br><b>${UI.escapeHtml(r.asesorInterno ? UI.formatPersonName(r.asesorInterno) : 'POR ASIGNAR')}</b></div>
            <div><span class="text-[#6e6e73]">Asesor Externo (Empresa):</span><br><b>${UI.escapeHtml(r.asesorExterno ? UI.formatPersonName(r.asesorExterno) : '—')}</b></div>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-8 pt-10 text-center text-[11px]">
          <div>
            <div class="border-t border-black/40 pt-2 font-semibold">Oficina de Gestión y Vinculación</div>
            <div class="text-[#6e6e73]">Control de Residencias Profesionales</div>
          </div>
          <div>
            <div class="border-t border-black/40 pt-2 font-semibold">Presidente de Academia de Ing. Industrial</div>
            <div class="text-[#6e6e73]">Vo. Bo. y Asignación de Asesor Interno</div>
          </div>
        </div>
      </div>
    `;

    modal.classList.remove('hidden');
  }

  function closeOficioModal() {
    document.getElementById('oficio-modal')?.classList.add('hidden');
  }

  // =========================================================================
  // MODAL DE AVISO POR CORREO INSTITUCIONAL (OUTLOOK)
  // =========================================================================
  function openOutlookModal(id) {
    const r = Store.getById(id);
    if (!r) return;

    const modal = document.getElementById('outlook-modal');
    if (!modal) return;

    const correoDefault = r.correoInstitucional || (r.control ? `l${r.control}@cdmadero.tecnm.mx` : '');
    const pa = r.oficioAutorizacion || 'En proceso';
    const pb = r.oficioAsesorInterno || 'En proceso';
    const asesor = r.asesorInterno ? UI.formatPersonName(r.asesorInterno) : 'Por asignar';
    const nombreAlumno = UI.formatPersonName(r.nombre);

    document.getElementById('outlook-exp-id').value = String(r.id);
    document.getElementById('outlook-modal-sub').textContent = `${nombreAlumno} · Control ${r.control}`;
    document.getElementById('outlook-to').value = correoDefault;
    document.getElementById('outlook-subject').value = `Residencias Profesionales · Oficios listos para recoger (${r.control})`;
    document.getElementById('outlook-body').value =
      `Estimado(a) ${nombreAlumno} (N° Control: ${r.control}):\n\n` +
      `Te informamos que tu trámite de Residencias Profesionales de Ingeniería Industrial ya cuenta con los documentos listos para recoger en la oficina:\n\n` +
      `• Proyecto: ${r.proyecto ? UI.formatTitleText(r.proyecto) : 'Registrado'}\n` +
      `• Oficio de Autorización (P.A): ${pa}\n` +
      `• Oficio de Asignación de Asesor (P.B): ${pb}\n` +
      `• Asesor Interno asignado: ${asesor}\n\n` +
      `Favor de pasar a la Coordinación de Residencias Profesionales en horario de atención.\n\n` +
      `Atentamente,\nCoordinación de Residencias Profesionales · Ingeniería Industrial · TecNM`;

    const badge = document.getElementById('outlook-smtp-badge');
    const oStatus = Store.getOutlookStatus();
    if (badge) {
      if (oStatus && oStatus.smtpConfigured) {
        badge.innerHTML = `<span><b>SMTP Outlook activo:</b> enviará directo desde ${UI.escapeHtml(oStatus.senderEmail)}</span>`;
      } else {
        badge.innerHTML = '<span>Usa <b>"Abrir en Outlook Web"</b> para enviar con tu sesión institucional abierta en 1 clic (o configura OUTLOOK_EMAIL/PASSWORD para SMTP directo).</span>';
      }
    }

    modal.classList.remove('hidden');
  }

  function closeOutlookModal() {
    document.getElementById('outlook-modal')?.classList.add('hidden');
  }

  async function handleSendOutlook(modo) {
    const id = Number(document.getElementById('outlook-exp-id')?.value || 0);
    const correo = (document.getElementById('outlook-to')?.value || '').trim();
    const asunto = (document.getElementById('outlook-subject')?.value || '').trim();
    const mensaje = (document.getElementById('outlook-body')?.value || '').trim();
    if (!id) return;

    try {
      const res = await Store.gestionEnviarAvisoOutlook(id, {
        correoDestino: correo,
        asunto,
        mensaje,
        modo
      });

      if (modo === 'smtp' && res.needsConfig) {
        UI.showToast(res.message || 'Sin credenciales SMTP configuradas. Usa "Abrir en Outlook Web".', 'warning');
        return;
      }

      if (modo === 'outlook_web' && res.outlookWebUrl) {
        window.open(res.outlookWebUrl, '_blank', 'noopener');
      }

      closeOutlookModal();
      refreshAll();
      UI.showToast(
        res.sentViaSmtp
          ? `Correo enviado vía Outlook SMTP a ${correo}`
          : `Aviso registrado en bitácora y redactado en Outlook Web para ${correo}`,
        'success'
      );
    } catch (err) {
      UI.showToast(err.message, 'error');
    }
  }

  // =========================================================================
  // BÚSQUEDA GLOBAL SPOTLIGHT EN TOPBAR (⌘K / Ctrl+K)
  // =========================================================================
  function handleGlobalSearchInput(val) {
    const dropdown = document.getElementById('global-search-dropdown');
    if (!dropdown) return;

    const trimmed = val.trim();
    if (trimmed.length < 2) {
      dropdown.classList.add('hidden');
      return;
    }

    const matches = Store.queryExpedientes({ q: trimmed });
    const top = matches.slice(0, 6);

    if (top.length === 0) {
      dropdown.innerHTML = `<div class="p-4 text-xs text-[#6e6e73] text-center">Sin coincidencias para "${UI.escapeHtml(trimmed)}"</div>`;
      dropdown.classList.remove('hidden');
      return;
    }

    dropdown.innerHTML = top.map((r) => `
      <button type="button" data-action="global-search-pick" data-id="${r.id}"
        class="w-full text-left px-3.5 py-2.5 hover:bg-[#007aff]/[0.06] border-b border-black/[0.05] flex items-center justify-between gap-3 transition">
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <span class="num-tabular text-[11px] font-semibold text-[#007aff]">${UI.escapeHtml(r.control)}</span>
            <span class="text-xs font-semibold text-[#1d1d1f] truncate">${UI.escapeHtml(UI.formatPersonName(r.nombre))}</span>
          </div>
          <div class="text-[11px] text-[#6e6e73] truncate">${UI.escapeHtml(UI.formatTitleText(r.proyecto || r.empresa || 'Sin anteproyecto'))}</div>
        </div>
        <div class="shrink-0">${UI.renderStatusBadge(r.estado)}</div>
      </button>
    `).join('') + `
      <button type="button" data-action="global-search-all"
        class="w-full px-3.5 py-2 bg-[#fafafc] hover:bg-black/[0.04] text-xs font-semibold text-[#007aff] text-center">
        Ver los ${matches.length} resultados en la tabla →
      </button>
    `;
    dropdown.classList.remove('hidden');
  }

  function closeMobileSidebar() {
    document.body.classList.remove('mobile-sidebar-open');
  }

  function renderConnectionStatus() {
    const info = Store.getConnectionInfo();
    const dot = document.getElementById('db-status-dot');
    const label = document.getElementById('db-status-label');
    const syncLabel = document.getElementById('btn-sync-label');
    const footerRole = document.getElementById('footer-role-indicator');
    const roleMeta = Store.getRoleMeta();

    if (dot) {
      dot.style.background = info.connected ? '#34c759' : '#86868b';
    }
    if (label) {
      label.textContent = info.connected ? `PostgreSQL · ${info.dbUser}` : 'Modo Local (Offline)';
    }
    if (syncLabel) {
      syncLabel.textContent = info.connected ? 'Sync' : 'Reset';
    }
    if (footerRole) {
      footerRole.textContent = `${roleMeta.label} · ${info.modeLabel}`;
    }
  }

  function refreshAll() {
    renderSidebar();
    renderTopbar();
    renderActiveView();
    renderConnectionStatus();
    if (appState.selectedId) {
      openDetailDrawer(appState.selectedId);
    }
  }

  // =========================================================================
  // DELEGACIÓN GLOBAL DE EVENTOS
  // =========================================================================
  function bindEvents() {
    document.addEventListener('click', async (e) => {
      const target = e.target.closest('[data-action]');
      if (!target) {
        const searchBox = document.getElementById('global-search-wrapper');
        const dropdown = document.getElementById('global-search-dropdown');
        if (dropdown && searchBox && !searchBox.contains(e.target)) {
          dropdown.classList.add('hidden');
        }
        return;
      }

      const action = target.dataset.action;
      const id = target.dataset.id ? Number(target.dataset.id) : null;

      switch (action) {
        case 'toggle-mobile-sidebar':
          document.body.classList.toggle('mobile-sidebar-open');
          break;
        case 'close-mobile-sidebar':
          closeMobileSidebar();
          break;
        case 'switch-role': {
          const newRole = target.dataset.role;
          const meta = Store.setRole(newRole);
          appState.academiaEditUnlocked = false;
          closeDetailDrawer();
          navigateTo(meta.defaultView, meta.isAcademia ? 'bandeja' : undefined);
          UI.showToast(`Perfil activo: ${meta.label}`, 'info');
          break;
        }
        case 'navigate':
          navigateTo(target.dataset.view, target.dataset.subtab);
          break;
        case 'new-solicitud':
          resetSolicitudForm();
          navigateTo('registro');
          break;
        case 'open-detail':
          if (id) openDetailDrawer(id);
          break;
        case 'close-detail':
          closeDetailDrawer();
          break;
        case 'edit-in-form':
          if (id) {
            closeDetailDrawer();
            loadRecordIntoForm(id);
          }
          break;
        case 'kpi-filter': {
          const kpisEl = document.getElementById('expedientes-kpis');
          const idx = Number(target.dataset.kpiIdx);
          const card = kpisEl && kpisEl._cards ? kpisEl._cards[idx] : null;
          if (card) {
            appState.filters.estado = card.filter.estado || 'ALL';
            appState.filters.servicioSocial = card.filter.servicioSocial || 'ALL';
            appState.currentPage = 1;
            renderExpedientesView();
          }
          break;
        }
        case 'toggle-advanced-filters': {
          appState.advancedFiltersOpen = !appState.advancedFiltersOpen;
          const panel = document.getElementById('advanced-filters-panel');
          if (panel) panel.classList.toggle('hidden', !appState.advancedFiltersOpen);
          break;
        }
        case 'clear-filters':
          appState.filters = {
            q: '', semestre: 'ALL', estado: 'ALL', servicioSocial: 'ALL',
            especialidad: 'ALL', asesor: 'ALL', empresa: 'ALL',
            oficioFilter: 'ALL', sortBy: 'id', sortDir: 'asc'
          };
          appState.currentPage = 1;
          renderExpedientesView();
          break;
        case 'remove-chip': {
          const k = target.dataset.chipKey;
          if (k === 'q') appState.filters.q = '';
          else if (k in appState.filters) appState.filters[k] = 'ALL';
          appState.currentPage = 1;
          renderExpedientesView();
          break;
        }
        case 'toggle-density':
          appState.tableDensity = appState.tableDensity === 'comfortable' ? 'compact' : 'comfortable';
          target.textContent = appState.tableDensity === 'compact' ? 'Vista Cómoda' : 'Vista Compacta';
          renderExpedientesView();
          break;
        case 'prev-page':
          if (appState.currentPage > 1) {
            appState.currentPage -= 1;
            renderExpedientesView();
          }
          break;
        case 'next-page':
          appState.currentPage += 1;
          renderExpedientesView();
          break;
        case 'export-csv': {
          const rows = Store.queryExpedientes(appState.filters);
          Store.exportToCSV(rows);
          UI.showToast(`Exportados ${rows.length} expedientes a CSV`, 'success');
          break;
        }
        case 'suggest-pa': {
          const folio = Store.getNextFolio('PA', 2026);
          document.getElementById('f-oficio-aut').value = folio;
          updateFormLivePreview();
          UI.showToast(`Folio sugerido: ${folio}`, 'info');
          break;
        }
        case 'suggest-pb': {
          const folio = Store.getNextFolio('PB', 2026);
          document.getElementById('f-oficio-asesor').value = folio;
          updateFormLivePreview();
          UI.showToast(`Folio sugerido: ${folio}`, 'info');
          break;
        }
        case 'set-today': {
          const targetId = target.dataset.targetInput;
          const inp = document.getElementById(targetId);
          if (inp) {
            inp.value = Store.todayISO();
            updateFormLivePreview();
          }
          break;
        }
        case 'unlock-academia':
          appState.academiaEditUnlocked = !appState.academiaEditUnlocked;
          applyRolePermissionsToForm();
          break;
        case 'reset-form':
          resetSolicitudForm();
          break;
        case 'emitir-pa': {
          try {
            const rec = await Store.gestionAceptarProyecto(id);
            if (rec) {
              UI.showToast(`Oficio ${rec.oficioAutorizacion} emitido`, 'success');
              refreshAll();
            }
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'emitir-pb': {
          try {
            const rec = await Store.gestionEmitirOficioAsesor(id);
            if (rec) {
              UI.showToast(`Oficio ${rec.oficioAsesorInterno} emitido`, 'success');
              refreshAll();
            }
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'open-outlook-modal':
        case 'notificar-alumno':
          if (id) openOutlookModal(id);
          break;
        case 'close-outlook-modal':
          closeOutlookModal();
          break;
        case 'send-outlook-web':
          await handleSendOutlook('outlook_web');
          break;
        case 'send-outlook-smtp':
          await handleSendOutlook('smtp');
          break;
        case 'preview-oficio':
          if (id) openOficioModal(id);
          break;
        case 'close-oficio-modal':
          closeOficioModal();
          break;
        case 'print-oficio':
          window.print();
          break;
        case 'switch-oficios-subtab':
          appState.oficiosSubtab = target.dataset.oficiosSubtab;
          renderOficiosView();
          break;
        case 'switch-academia-subtab':
          appState.academiaSubtab = target.dataset.academiaSubtab;
          renderSidebar();
          renderTopbar();
          renderAcademiaView();
          break;
        case 'acad-assign': {
          const sel = document.getElementById(`acad-select-${id}`);
          const fol = document.getElementById(`acad-folio-${id}`);
          const chosen = sel ? sel.value : '';
          const rec = Store.getById(id);
          const asesorFinal = chosen || (rec ? rec.asesorInterno : '');
          if (!asesorFinal) {
            UI.showToast('Selecciona un docente de la lista', 'warning');
            return;
          }
          try {
            const updated = await Store.academiaAsignarAsesor(id, {
              asesorInterno: asesorFinal,
              folioAcademia: fol ? fol.value : undefined,
              autoOficioPB: false,
              correccionAdmin: Store.getRoleMeta().isGestion
            });
            UI.showToast(`Asesor ${UI.formatPersonName(updated.asesorInterno)} asignado`, 'success');
            refreshAll();
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'drawer-assign-asesor': {
          const sel = document.getElementById('drawer-asesor-select');
          const fol = document.getElementById('drawer-folio-input');
          try {
            const updated = await Store.academiaAsignarAsesor(id, {
              asesorInterno: sel ? sel.value : '',
              folioAcademia: fol ? fol.value : '',
              autoOficioPB: false,
              correccionAdmin: Store.getRoleMeta().isGestion
            });
            UI.showToast(`Asesor guardado: ${UI.formatPersonName(updated.asesorInterno)}`, 'success');
            refreshAll();
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'drawer-toggle-pause': {
          const rec = Store.getById(id);
          if (!rec) return;
          const nextEstado = rec.estado === 'Pausado / Sin Oficio'
            ? (rec.asesorInterno && rec.oficioAsesorInterno ? 'Expediente Completo' : 'En Revisión por Academia')
            : 'Pausado / Sin Oficio';
          const obs = nextEstado === 'Pausado / Sin Oficio'
            ? 'Trámite marcado como pausado / inconcluso por el alumno.'
            : 'Trámite reactivado desde oficina de Gestión.';
          try {
            await Store.cambiarExcepcion(id, { estado: nextEstado, observaciones: obs });
            UI.showToast(`Estado: ${nextEstado}`, 'info');
            refreshAll();
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'drawer-cycle-ss': {
          const rec = Store.getById(id);
          if (!rec) return;
          const order = ['Liberado', 'Por verificar', 'No Liberado (Irregular)'];
          const idx = order.indexOf(rec.servicioSocial);
          const nextSS = order[(idx + 1) % order.length];
          try {
            await Store.cambiarExcepcion(id, { servicioSocial: nextSS });
            UI.showToast(`Servicio Social: ${nextSS}`, nextSS === 'No Liberado (Irregular)' ? 'warning' : 'success');
            refreshAll();
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'filter-by-teacher': {
          const teacher = target.dataset.teacher || '';
          const firstToken = teacher.split(' ')[0] || teacher;
          appState.filters.q = firstToken;
          appState.currentPage = 1;
          navigateTo('expedientes');
          break;
        }
        case 'switch-exc-subtab':
          appState.excepcionesSubtab = target.dataset.excSubtab;
          renderExcepcionesView();
          break;
        case 'reactivar-tramite': {
          try {
            await Store.cambiarExcepcion(id, {
              estado: 'En Revisión por Academia',
              observaciones: 'Trámite reactivado para continuar revisión.'
            });
            UI.showToast('Trámite reactivado', 'success');
            refreshAll();
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'ss-confirm-ok': {
          try {
            await Store.cambiarExcepcion(id, {
              servicioSocial: 'Liberado',
              observaciones: 'Constancia de Servicio Social verificada y liberada.'
            });
            UI.showToast('Servicio Social confirmado', 'success');
            refreshAll();
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'ss-block': {
          try {
            await Store.cambiarExcepcion(id, {
              estado: 'Detenido por Servicio Social',
              servicioSocial: 'No Liberado (Irregular)',
              observaciones: 'Alumno entregó hojas impresas sin haber acreditado Servicio Social.'
            });
            UI.showToast('Bloqueado por falta de S.S.', 'warning');
            refreshAll();
          } catch (err) {
            UI.showToast(err.message, 'error');
          }
          break;
        }
        case 'global-search-pick':
          document.getElementById('global-search-dropdown')?.classList.add('hidden');
          if (id) openDetailDrawer(id);
          break;
        case 'global-search-all': {
          const val = document.getElementById('global-search-input')?.value || '';
          document.getElementById('global-search-dropdown')?.classList.add('hidden');
          appState.filters.q = val.trim();
          appState.currentPage = 1;
          navigateTo('expedientes');
          break;
        }
        case 'open-shortcuts':
          document.getElementById('shortcuts-modal')?.classList.remove('hidden');
          break;
        case 'close-shortcuts':
          document.getElementById('shortcuts-modal')?.classList.add('hidden');
          break;
        case 'reset-database':
          if (Store.getConnectionInfo().connected) {
            try {
              await Store.syncFromServer();
              closeDetailDrawer();
              refreshAll();
              UI.showToast('Sincronizado con PostgreSQL 16', 'success');
            } catch (err) {
              UI.showToast(err.message, 'error');
            }
          } else if (confirm('¿Restaurar los 144 expedientes y 42 docentes originales en modo local?')) {
            Store.reset();
            closeDetailDrawer();
            refreshAll();
            UI.showToast('Base de datos local restaurada', 'info');
          }
          break;
      }
    });

    const bindFilter = (id, key, isNum = false) => {
      const el = document.getElementById(id);
      if (!el) return;
      const evt = el.tagName === 'INPUT' ? 'input' : 'change';
      el.addEventListener(evt, () => {
        if (key === 'pageSize') {
          appState.pageSize = Number(el.value);
        } else {
          appState.filters[key] = isNum ? Number(el.value) : el.value;
        }
        appState.currentPage = 1;
        renderExpedientesView();
      });
    };

    bindFilter('filter-q', 'q');
    bindFilter('filter-semestre', 'semestre');
    bindFilter('filter-estado', 'estado');
    bindFilter('filter-ss', 'servicioSocial');
    bindFilter('filter-asesor', 'asesor');
    bindFilter('filter-especialidad', 'especialidad');
    bindFilter('filter-empresa', 'empresa');
    bindFilter('filter-oficio', 'oficioFilter');
    bindFilter('sort-by', 'sortBy');
    bindFilter('page-size', 'pageSize', true);

    const globalSearch = document.getElementById('global-search-input');
    if (globalSearch) {
      globalSearch.addEventListener('input', (e) => handleGlobalSearchInput(e.target.value));
      globalSearch.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          document.getElementById('global-search-dropdown')?.classList.add('hidden');
          appState.filters.q = globalSearch.value.trim();
          appState.currentPage = 1;
          navigateTo('expedientes');
        }
      });
    }

    document.getElementById('filter-maestro-q')?.addEventListener('input', (e) => {
      appState.maestrosFilter.q = e.target.value;
      renderMaestrosMatrix();
    });
    document.getElementById('filter-maestro-jornada')?.addEventListener('change', (e) => {
      appState.maestrosFilter.jornada = e.target.value;
      renderMaestrosMatrix();
    });
    document.getElementById('filter-maestro-beca')?.addEventListener('change', (e) => {
      appState.maestrosFilter.beca = e.target.value;
      renderMaestrosMatrix();
    });

    document.getElementById('exc-search')?.addEventListener('input', () => renderExcepcionesView());

    document.getElementById('bitacora-q')?.addEventListener('input', (e) => {
      appState.bitacoraFilter.q = e.target.value;
      renderBitacoraView();
    });
    document.getElementById('bitacora-usuario')?.addEventListener('change', (e) => {
      appState.bitacoraFilter.usuario = e.target.value;
      renderBitacoraView();
    });

    const form = document.getElementById('form-solicitud');
    if (form) {
      form.addEventListener('submit', handleSaveSolicitudForm);
      form.addEventListener('input', () => updateFormLivePreview());
      form.addEventListener('change', () => updateFormLivePreview());
    }

    document.getElementById('f-control')?.addEventListener('input', (e) => {
      handleControlLookup(e.target.value);
    });

    document.querySelectorAll('input[name="f-ss-radio"]').forEach((radio) => {
      radio.addEventListener('change', (e) => {
        syncSSRadioCards(e.target.value);
        if (e.target.value === 'No Liberado (Irregular)') {
          document.getElementById('f-estado').value = 'Detenido por Servicio Social';
          const obsEl = document.getElementById('f-observaciones');
          if (obsEl && !obsEl.value) {
            obsEl.value = 'Alumno entregó solicitud sin haber liberado su Servicio Social.';
          }
        }
        updateFormLivePreview();
      });
    });

    document.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        document.getElementById('global-search-input')?.focus();
      } else if (e.key === '/' && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName)) {
        e.preventDefault();
        document.getElementById('global-search-input')?.focus();
      } else if (e.key === 'Escape') {
        closeDetailDrawer();
        closeOficioModal();
        closeOutlookModal();
        closeMobileSidebar();
        document.getElementById('shortcuts-modal')?.classList.add('hidden');
        document.getElementById('global-search-dropdown')?.classList.add('hidden');
      }
    });
  }

  document.addEventListener('DOMContentLoaded', async () => {
    await Store.init();
    bindEvents();
    const roleMeta = Store.getRoleMeta();
    navigateTo(roleMeta.defaultView, roleMeta.isAcademia ? 'bandeja' : undefined);
    renderConnectionStatus();
  });
})(window);
