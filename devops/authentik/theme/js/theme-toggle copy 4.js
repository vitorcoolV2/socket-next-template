(function () {
    const run = () => {
        // 1. Identifica o Root e a Interface de Apresentação
        const root = document.querySelector('ak-interface-user') || document.querySelector('ak-interface-admin');
        if (!root) return;

        const pres = root.shadowRoot?.querySelector('[class*="-presentation"]') ||
            root.shadowRoot?.querySelector('ak-interface-user-presentation') ||
            root.shadowRoot?.querySelector('ak-interface-admin-presentation');

        if (!pres || !pres.shadowRoot) return;

        // 2. Localiza o local de injeção no Shadow DOM
        const target = pres.shadowRoot.querySelector('.pf-c-page__header-tools-group');

        if (target && !pres.shadowRoot.getElementById('home2500-toggle')) {
            const div = document.createElement('div');
            div.className = 'pf-c-page__header-tools-item';
            div.id = 'home2500-toggle';

            // O tema atual vem da propriedade 'theme' do componente
            const currentTheme = pres.theme || 'dark';
            div.innerHTML = `<button class="pf-c-button pf-m-plain" type="button" style="cursor:pointer">
                                ${currentTheme === 'dark' ? '🌙 Dark' : '☀️ Light'}
                             </button>`;

            div.onclick = () => {
                const root = document.querySelector('ak-interface-user') || document.querySelector('ak-interface-admin');
                const current = root.getAttribute('theme') || 'dark';
                const next = current === 'dark' ? 'light' : 'dark';

                // 1. Atualiza o Root e o HTML
                document.documentElement.setAttribute('data-theme', next);
                root.setAttribute('theme', next);
                localStorage.setItem('ak-theme', next);

                // 2. Função Recursiva para furar todos os Shadow DOMs
                const updateAllComponents = (container) => {
                    if (!container) return;

                    // Procura todos os elementos que começam por "ak-"
                    const elements = container.querySelectorAll('*');
                    elements.forEach(el => {
                        if (el.tagName.startsWith('ak-') && 'theme' in el) {
                            el.theme = next;
                            el.setAttribute('theme', next);
                            if (typeof el.requestUpdate === 'function') {
                                el.requestUpdate();
                            }
                        }
                        // Se o elemento tem a sua própria "sombra", entra nela
                        if (el.shadowRoot) {
                            updateAllComponents(el.shadowRoot);
                        }
                    });
                };

                // Inicia a caça a partir do root e da sua sombra
                updateAllComponents(root.shadowRoot);

                // 3. Força o reload do teu CSS
                const link = document.querySelector('link[href*="custom.css"]');
                if (link) link.href = link.href.split('?')[0] + '?v=' + Date.now();

                console.log(`🚀 Deep Update: Todos os componentes ak-* forçados para ${next}`);
            };

            target.prepend(div);
        }
    };

    // Executa a cada 2s para lidar com navegação SPA do Authentik
    setInterval(run, 2000);
})();