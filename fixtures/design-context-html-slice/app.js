(() => {
  'use strict';

  window.LucideSubset.render(document);

  const tabs = [...document.querySelectorAll('[role="tab"]')];
  const panels = [...document.querySelectorAll('[data-stage-panel]')];
  const activateStage = (stage, focus = false) => {
    tabs.forEach((tab) => {
      const selected = tab.dataset.stage === stage;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
      if (selected && focus) tab.focus();
    });
    panels.forEach((panel) => { panel.hidden = panel.dataset.stagePanel !== stage; });
  };

  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => activateStage(tab.dataset.stage));
    tab.addEventListener('keydown', (event) => {
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      let next = index;
      if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      activateStage(tabs[next].dataset.stage, true);
    });
  });

  document.querySelectorAll('.context-trigger').forEach((button) => {
    button.addEventListener('click', () => {
      const item = button.closest('.context-item');
      const detail = document.getElementById(button.getAttribute('aria-controls'));
      const willOpen = button.getAttribute('aria-expanded') !== 'true';
      button.setAttribute('aria-expanded', String(willOpen));
      detail.hidden = !willOpen;
      item.classList.toggle('is-open', willOpen);
    });
  });

  activateStage('before');
})();
