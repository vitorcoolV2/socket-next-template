(function () {
    const run = () => {
        // 1. Captura todos os componentes Authentik no topo (admin, user, messages, etc.)
        const roots = Array.from(document.querySelectorAll('body > *')).filter(n => n.tagName.startsWith('AK-'));

        if (roots.length === 0) return;

        // 2. Localiza o ponto de injeção (Header) no componente de interface principal
        const mainInterface = roots.find(el => el.tagName.includes('INTERFACE'));
        const pres = mainInterface?.shadowRoot?.querySelector('[class*="-presentation"]') ||
            mainInterface?.shadowRoot?.querySelector('ak-interface-user-presentation');

        if (pres?.shadowRoot) {
            const target = pres.shadowRoot.querySelector('.pf-c-page__header-tools-group');

            if (target && !pres.shadowRoot.getElementById('home2500-toggle')) {
                const div = document.createElement('div');
                div.className = 'pf-c-page__header-tools-item';
                div.id = 'home2500-toggle';
                // Adicionamos uma margem para não colar no search
                div.style.marginRight = "10px";

                const currentTheme = mainInterface.getAttribute('theme') || 'dark';
                div.innerHTML = `<button class="pf-c-button pf-m-plain" type="button" style="font-size:1.1rem; cursor:pointer; padding: 0 8px;">
                                    ${currentTheme === 'dark' ? '🌙' : '☀️'}
                                </button>`;

                // Em vez de prepend, vamos inserir antes do primeiro ícone de notificação
                // ou simplesmente usar o append para ficar no fim da fila
                target.appendChild(div);

                div.onclick = () => {
                    const next = (mainInterface.getAttribute('theme') === 'dark') ? 'light' : 'dark';

                    // A. Sincronização Global
                    document.documentElement.setAttribute('data-theme', next);
                    localStorage.setItem('ak-theme', next);

                    // B. FUNÇÃO DE PROFUNDIDADE: Ataca todos os roots e seus descendentes
                    const deepUpdate = (node) => {
                        if (!node) return;

                        if (node.tagName && node.tagName.startsWith('AK-')) {
                            if ('theme' in node || node.hasAttribute('theme')) {
                                node.theme = next;
                                node.setAttribute('theme', next);
                                if (typeof node.requestUpdate === 'function') node.requestUpdate();
                            }
                        }

                        if (node.shadowRoot) deepUpdate(node.shadowRoot);

                        for (let child of node.children || []) {
                            deepUpdate(child);
                        }
                    };

                    // Aplica em todos os componentes detectados no body
                    roots.forEach(root => deepUpdate(root));

                    // C. Force Reload CSS
                    const link = document.querySelector('link[href*="custom.css"]');
                    if (link) link.href = link.href.split('?')[0] + '?v=' + Date.now();

                    div.querySelector('button').innerHTML = next === 'dark' ? '🌙' : '☀️';
                };

                target.prepend(div);
            }
        }
    };

    setInterval(run, 2000);
})();