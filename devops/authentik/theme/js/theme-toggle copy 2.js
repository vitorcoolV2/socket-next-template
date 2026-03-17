(function () {
    const run = () => {
        const h1 = document.querySelector('ak-interface-user') || document.querySelector('ak-interface-admin');
        const h2 = h1?.shadowRoot?.querySelector('ak-interface-user-presentation') || h1?.shadowRoot?.querySelector('ak-interface-admin-presentation');
        const target = h2?.shadowRoot?.querySelector('.pf-c-page__header-tools-group');

        if (target && !h2.shadowRoot.getElementById('home2500-toggle')) {
            const div = document.createElement('div');
            div.className = 'pf-c-page__header-tools-item';
            div.id = 'home2500-toggle';

            // Criamos o botão com o estilo nativo do PatternFly (estilo do Authentik)
            div.innerHTML = `<button class="pf-c-button pf-m-plain" type="button" aria-label="Toggle Theme">
                                <i class="fas fa-moon" aria-hidden="true"></i>
                             </button>`;

            div.onclick = () => {
                const html = document.documentElement;
                // 1. Detetar o tema atual
                const currentTheme = html.getAttribute('data-theme') || 'light';
                const nextTheme = currentTheme === 'dark' ? 'light' : 'dark';

                // 2. Aplicar no HTML (muda as variáveis CSS globais)
                html.setAttribute('data-theme', nextTheme);

                // 3. Persistir para o próximo refresh
                localStorage.setItem('ak-theme', nextTheme);

                // 4. Update visual do ícone (opcional)
                const icon = div.querySelector('i');
                icon.className = nextTheme === 'dark' ? 'fas fa-moon' : 'fas fa-sun';

                console.log(`🌓 Tema alterado para: ${nextTheme}`);
            };

            target.prepend(div);
        }
    };

    // Mantemos o intervalo para garantir que o botão sobrevive a navegações SPA
    setInterval(run, 2000);

    // No primeiro load, verificamos se há preferência salva
    const saved = localStorage.getItem('ak-theme');
    if (saved) document.documentElement.setAttribute('data-theme', saved);
})();