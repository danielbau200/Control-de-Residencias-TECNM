const SESSION_KEY = 'tecnm.session';
const SUBJECT_KEY = 'tecnm.subject';

function getSession() {
  try {
    return JSON.parse(sessionStorage.getItem(SESSION_KEY) || 'null');
  } catch {
    return null;
  }
}

function getSelectedSubject() {
  const params = new URLSearchParams(window.location.search);
  const queryName = params.get('nombre');
  const queryKey = params.get('clave');
  const querySemester = params.get('semestre');
  if (queryName && queryKey) {
    return { name: queryName, clave: queryKey, semester: querySemester || '-' };
  }

  try {
    return JSON.parse(sessionStorage.getItem(SUBJECT_KEY) || 'null');
  } catch {
    return null;
  }
}

function redirectTo(path) {
  window.location.assign(new URL(path, window.location.href).href);
}

function protectPages() {
  const page = window.location.pathname.split('/').pop();
  const publicPages = ['login.html', 'gestion-vinculacion.html', 'index.html', ''];
  if (!publicPages.includes(page) && !getSession()) {
    redirectTo('login.html');
  }
}

function setupLogin() {
  const form = document.querySelector('#login-form');
  if (!form) return;

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const button = form.querySelector('button[type="submit"]');
    const identifier = form.querySelector('[name="identifier"]').value.trim();

    if (!button || !identifier) return;

    const originalContent = button.innerHTML;
    button.disabled = true;
    button.innerHTML = '<span class="material-symbols-outlined text-base animate-spin">progress_activity</span><span>Verificando...</span>';

    window.setTimeout(() => {
      sessionStorage.setItem(SESSION_KEY, JSON.stringify({
        identifier,
        name: 'Daniel Bautista',
        createdAt: new Date().toISOString()
      }));
      button.innerHTML = '<span class="material-symbols-outlined text-base">check</span><span>Acceso acreditado</span>';
      window.setTimeout(() => redirectTo('reticula.html'), 500);
    }, 700);

    button.dataset.originalContent = originalContent;
  });

  const password = document.querySelector('#user-password');
  const toggle = document.querySelector('[data-action="toggle-password"]');
  if (password && toggle) {
    toggle.addEventListener('click', () => {
      const visible = password.type === 'text';
      password.type = visible ? 'password' : 'text';
      toggle.querySelector('span').textContent = visible ? 'visibility' : 'visibility_off';
    });
  }
}

function setupSessionUi() {
  const session = getSession();
  document.querySelectorAll('[data-user-name]').forEach((element) => {
    element.textContent = session?.name || 'Estudiante';
  });

  document.querySelectorAll('[data-action="logout"]').forEach((button) => {
    button.addEventListener('click', () => {
      sessionStorage.removeItem(SESSION_KEY);
      redirectTo('login.html');
    });
  });
}

function setupNavigation() {
  const currentPage = window.location.pathname.split('/').pop();
  document.querySelectorAll('[data-nav]').forEach((link) => {
    if (link.getAttribute('href') === currentPage) {
      link.setAttribute('aria-current', 'page');
    }
  });
}

function setupSubjectPage() {
  const subject = getSelectedSubject();
  if (!subject || !document.querySelector('[data-subject-title]')) return;

  document.querySelectorAll('[data-subject-title]').forEach((element) => {
    element.textContent = subject.name;
  });
  document.querySelectorAll('[data-subject-key]').forEach((element) => {
    element.textContent = `CLAVE ${subject.clave}`;
  });
  document.querySelectorAll('[data-subject-semester]').forEach((element) => {
    element.textContent = `Semestre ${subject.semester}`;
  });
}

window.goToSubject = function goToSubject() {
  redirectTo('temario.html');
};

// ==========================================================================
// Navigation Drawer Controller (Voxelcost Interaction Pattern)
// ==========================================================================
(function setupNavDrawerController() {
  let isPinned = false;
  let isHovered = false;
  let closeTimer = null;
  const HOVER_DELAY_MS = 350;

  function isHoverCapable() {
    return window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  }

  function clearCloseTimer() {
    if (closeTimer) {
      clearTimeout(closeTimer);
      closeTimer = null;
    }
  }

  function syncButtons() {
    const buttons = document.querySelectorAll('#hamburger-btn, .sidebar-toggle-btn');
    const isOpen = document.body.classList.contains('drawer-open');
    buttons.forEach((btn) => {
      btn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      btn.setAttribute('aria-pressed', isPinned ? 'true' : 'false');
      if (isPinned) {
        btn.classList.add('is-pinned');
      } else {
        btn.classList.remove('is-pinned');
      }
    });
  }

  function openDrawer(pinned = false) {
    clearCloseTimer();
    document.body.classList.add('drawer-open');
    if (pinned) {
      isPinned = true;
      document.body.classList.add('drawer-pinned');
    }
    syncButtons();
  }

  function closeDrawer(force = false) {
    clearCloseTimer();

    if (force) {
      isPinned = false;
    }

    // While pinned, ignore hover leave
    if (isPinned && !force) {
      return;
    }

    document.body.classList.remove('drawer-open');
    document.body.classList.remove('drawer-pinned');
    syncButtons();
  }

  function scheduleClose() {
    if (isPinned) return;
    clearCloseTimer();
    closeTimer = setTimeout(() => {
      if (!isHovered && !isPinned) {
        closeDrawer(false);
      }
    }, HOVER_DELAY_MS);
  }

  function togglePinned() {
    clearCloseTimer();
    if (isPinned) {
      // Unpin
      isPinned = false;
      document.body.classList.remove('drawer-pinned');
      // If cursor is still inside area, keep open in temporary hover mode
      if (!isHovered) {
        closeDrawer(true);
      } else {
        syncButtons();
      }
    } else {
      openDrawer(true);
    }
  }

  // Global helper accessible anywhere
  window.toggleMenu = function toggleMenu(forceState) {
    if (typeof forceState === 'boolean') {
      if (forceState) openDrawer(true);
      else closeDrawer(true);
    } else {
      togglePinned();
    }
  };

  window.closeNavDrawer = function closeNavDrawer() {
    isHovered = false;
    closeDrawer(true);
  };

  function initNavDrawer() {
    const btn = document.getElementById('hamburger-btn');
    const drawer = document.getElementById('nav-drawer');
    const backdrop = document.getElementById('nav-backdrop');

    if (!drawer) return;

    // 1. Initial State: Closed & unpinned
    document.body.classList.remove('drawer-open', 'drawer-pinned');
    isPinned = false;
    isHovered = false;
    clearCloseTimer();
    syncButtons();

    // Hover listeners on trigger button and sidebar panel
    const hoverTargets = [btn, drawer].filter(Boolean);
    hoverTargets.forEach((target) => {
      target.addEventListener('mouseenter', () => {
        if (!isHoverCapable()) return;
        isHovered = true;
        clearCloseTimer();
        if (!isPinned) {
          openDrawer(false);
        }
      });

      target.addEventListener('mouseleave', () => {
        if (!isHoverCapable()) return;
        isHovered = false;
        scheduleClose();
      });
    });

    // 3. Toggle button clicks
    if (btn) {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        togglePinned();
      });
    }

    drawer.querySelectorAll('.sidebar-toggle-btn').forEach((toggleBtn) => {
      toggleBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        togglePinned();
      });
    });

    // Backdrop click (mobile/touch)
    if (backdrop) {
      backdrop.addEventListener('click', () => {
        isHovered = false;
        closeDrawer(true);
      });
    }

    // 5. Selection and Navigation:
    // When clicking any link or action inside drawer, close and unpin
    drawer.querySelectorAll('a, button[data-action="logout"], .nav-item-action').forEach((link) => {
      link.addEventListener('click', () => {
        isHovered = false;
        closeDrawer(true);
      });
    });

    // Escape key closes
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        isHovered = false;
        closeDrawer(true);
      }
    });

    // Cleanup on beforeunload
    window.addEventListener('beforeunload', () => {
      clearCloseTimer();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initNavDrawer);
  } else {
    initNavDrawer();
  }
})();

document.addEventListener('DOMContentLoaded', () => {
  protectPages();
  setupLogin();
  setupSessionUi();
  setupNavigation();
  setupSubjectPage();
});
