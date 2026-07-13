(() => {
  const SUPABASE_URL = 'https://qfwiizvqxrhjlthbjosz.supabase.co';
  const API_KEY = 'sb_publishable_RdaJXK16LieKNlJZjJJ7tQ_5vF9YkhF';
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  class TaptMenu extends HTMLElement {
    constructor() {
      super();
      this.root = this.attachShadow({ mode: 'open' });
    }

    connectedCallback() {
      const venue = this.getAttribute('venue') || '';
      if (!UUID.test(venue)) {
        this.renderMessage('This Tapt menu link is invalid.');
        return;
      }
      this.renderLoading();
      this.load(venue);
    }

    async rpc(name, venue) {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: API_KEY },
        body: JSON.stringify({ p_venue: venue })
      });
      if (!response.ok) throw new Error(`${name} failed`);
      return response.json();
    }

    async load(venue) {
      try {
        const [menus, brands, events] = await Promise.all([
          this.rpc('venue_menu', venue),
          this.rpc('venue_brand', venue),
          this.rpc('venue_events', venue)
        ]);
        const brand = Array.isArray(brands) ? brands[0] : null;
        if (!brand && (!Array.isArray(menus) || menus.length === 0)) {
          this.renderMessage('This venue does not have a published Tapt menu yet.');
          return;
        }
        this.renderMenu(venue, brand, Array.isArray(menus) ? menus : [], Array.isArray(events) ? events : []);
      } catch {
        this.renderMessage('This menu is unavailable right now.');
      }
    }

    shell(content) {
      this.root.innerHTML = `
        <style>
          :host{display:block;color:#1A1206;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
          *{box-sizing:border-box}
          .menu{overflow:hidden;background:#FBF6EC;border:1px solid rgba(26,18,6,.12);border-radius:8px}
          .head{display:flex;align-items:center;gap:12px;padding:18px 20px;background:#1A1206;color:#FBF6EC}
          .logo{width:46px;height:46px;object-fit:cover;border-radius:6px;background:#fff}
          .title{min-width:0;flex:1}.title b{display:block;font-size:1.1rem;line-height:1.2}.title span{display:block;margin-top:3px;color:rgba(251,246,236,.68);font-size:.78rem}
          .tapt{font-weight:800;color:#F2A900;font-size:.78rem;white-space:nowrap}
          .body{padding:12px 16px 16px}.tap{display:flex;justify-content:space-between;gap:14px;padding:11px 4px;border-bottom:1px solid rgba(26,18,6,.09)}
          .tap:last-child{border-bottom:0}.tap b{display:block;font-size:.96rem;line-height:1.25}.meta{margin-top:2px;color:#6B6459;font-size:.78rem}.price{font-weight:800;color:#B4531F;white-space:nowrap}
          .events{padding:10px 16px 0}.event{padding:9px 11px;margin-bottom:6px;background:#FFF3D6;border-left:3px solid #F2A900;border-radius:4px}.event b{font-size:.84rem}.event span{display:block;margin-top:2px;color:#6B6459;font-size:.73rem}
          .empty,.state{padding:28px 20px;text-align:center;color:#6B6459;font-size:.9rem}.state{background:#FBF6EC;border:1px solid rgba(26,18,6,.12);border-radius:8px}
          .foot{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 20px;background:#fff;border-top:1px solid rgba(26,18,6,.09);font-size:.76rem;color:#6B6459}.foot a{font-weight:700;color:#B4531F;text-decoration:none}
          @media(max-width:420px){.head{padding:15px}.body{padding-inline:12px}.tapt{display:none}.foot{padding-inline:15px}}
        </style>${content}`;
    }

    renderLoading() {
      this.shell('<div class="state" role="status">Loading the live tap list...</div>');
    }

    renderMessage(message) {
      this.shell('<div class="state" role="status"></div>');
      this.root.querySelector('.state').textContent = message;
    }

    renderMenu(venue, brand, menus, events) {
      this.shell(`
        <article class="menu">
          <header class="head">
            <img class="logo" hidden alt="">
            <div class="title"><b></b><span></span></div>
            <div class="tapt">Tapt.</div>
          </header>
          <div class="events" hidden></div>
          <div class="body"></div>
          <footer class="foot"><span></span><a target="_blank" rel="noopener">Open live menu</a></footer>
        </article>`);

      const name = brand?.name || menus[0]?.venue_name || 'Live tap list';
      const place = [brand?.city || menus[0]?.city, brand?.region || menus[0]?.region, brand?.country || menus[0]?.country].filter(Boolean).join(', ');
      this.root.querySelector('.title b').textContent = name;
      this.root.querySelector('.title span').textContent = place || 'Live tap list';

      if (brand?.logo_url) {
        const logo = this.root.querySelector('.logo');
        logo.src = brand.logo_url;
        logo.alt = `${name} logo`;
        logo.hidden = false;
      }

      const eventBox = this.root.querySelector('.events');
      events.slice(0, 3).forEach(item => {
        const event = document.createElement('div');
        event.className = 'event';
        const title = document.createElement('b');
        title.textContent = item.title;
        event.appendChild(title);
        if (item.starts_at) {
          const time = document.createElement('span');
          time.textContent = new Date(item.starts_at).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
          event.appendChild(time);
        }
        eventBox.appendChild(event);
      });
      eventBox.hidden = eventBox.childElementCount === 0;

      const body = this.root.querySelector('.body');
      if (menus.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'empty';
        empty.textContent = 'No current tap list has been published yet.';
        body.appendChild(empty);
      } else {
        menus.forEach(item => {
          const tap = document.createElement('div');
          tap.className = 'tap';
          const details = document.createElement('div');
          const beer = document.createElement('b');
          beer.textContent = item.beer_name;
          details.appendChild(beer);
          const metadata = [item.brewery_name, item.style].filter(Boolean).join(' · ');
          if (metadata) {
            const meta = document.createElement('div');
            meta.className = 'meta';
            meta.textContent = metadata;
            details.appendChild(meta);
          }
          tap.appendChild(details);
          if (item.price_text) {
            const price = document.createElement('div');
            price.className = 'price';
            price.textContent = item.price_text;
            tap.appendChild(price);
          }
          body.appendChild(tap);
        });
      }

      const updated = menus[0]?.updated_at;
      this.root.querySelector('.foot span').textContent = updated
        ? `Updated ${new Date(updated).toLocaleDateString()}`
        : 'Hosted free on Tapt';
      this.root.querySelector('.foot a').href = `https://taptbeer.com/menu?v=${encodeURIComponent(venue)}`;
    }
  }

  if (!customElements.get('tapt-menu')) customElements.define('tapt-menu', TaptMenu);
})();
