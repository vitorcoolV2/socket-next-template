(function () {
    const run = () => {
        const root = document.querySelector('ak-interface-user') || document.querySelector('ak-interface-admin');
        const presentation = root?.shadowRoot?.querySelector('ak-interface-user-presentation') ||
            root?.shadowRoot?.querySelector('ak-interface-admin-presentation');

        const target = presentation?.shadowRoot?.querySelector('.pf-c-page__header-tools-group');

        if (target && !presentation.shadowRoot.getElementById('home2500-toggle')) {
            const div = document.createElement('div');
            div.className = 'pf-c-page__header-tools-item';
            div.id = 'home2500-toggle';
            div.innerHTML = `<button class="pf-c-button pf-m-plain" type="button">🌓</button>`;

            div.onclick = () => {
                const html = document.documentElement;
                const current = html.getAttribute('data-theme') || 'dark';
                const next = current === 'dark' ? 'light' : 'dark';

                // 1. Muda o global (para o teu CSS customizado)
                html.setAttribute('data-theme', next);

                // 2. FORÇA O COMPONENTE DO AUTHENTIK (O segredo está aqui)
                // Mudamos o atributo no elemento que controla a UI
                if (presentation) {
                    presentation.setAttribute('theme', next);
                    // O Authentik usa Lit, às vezes mudar o atributo basta, 
                    // outras vezes temos de aceder à propriedade interna:
                    presentation.theme = next;
                }

                localStorage.setItem('ak-theme', next);
                console.log("🚀 Forced theme to:", next);
            };

            target.prepend(div);
        }
    };

    setInterval(run, 2000);
})();