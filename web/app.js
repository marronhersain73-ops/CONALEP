const sb=supabase.createClient(CONFIG.SUPABASE_URL,CONFIG.SUPABASE_ANON_KEY);
const $=s=>document.querySelector(s);
const esc=t=>String(t??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const CATS=['Credenciales','Electrónicos','Ropa','Útiles','Llaves','Otros'];
const ST={pendiente:'Pendiente',en_proceso:'En proceso',entregado:'Entregado'};
const COLS='id,user_id,title,description,location,category,type,image_url,delivery_status,created_at';
let me=null,prof=null,posts=[],people={},comms=[],reacts=[],timer;
const toast=m=>{const t=$('#toast');t.textContent=m;t.hidden=false;clearTimeout(t._h);t._h=setTimeout(()=>t.hidden=true,4000)};
const show=w=>{$('#auth').hidden=w!=='auth';$('#app').hidden=w!=='app'};
const run=async p=>{const{error}=await p;error?toast(error.message):load();return !error};
['#fcat','#ncat'].forEach(s=>CATS.forEach(c=>$(s).add(new Option(c))));

// ---- Sesión ----
sb.auth.onAuthStateChange((_e,s)=>{me=s?.user??null;setTimeout(async()=>{
 if(!me){prof=null;return show('auth')}
 const{data}=await sb.from('profiles').select('nombre,rol,estado').eq('id',me.id).single();prof=data;show('app');load();},0)});
document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{
 document.querySelectorAll('[data-tab]').forEach(x=>x.classList.toggle('on',x===b));
 $('#fin').hidden=b.dataset.tab!=='in';$('#fup').hidden=b.dataset.tab!=='up'});
$('#fin').onsubmit=async e=>{e.preventDefault();const f=Object.fromEntries(new FormData(e.target));
 const{error}=await sb.auth.signInWithPassword({email:f.email,password:f.password});if(error)toast('Correo o contraseña incorrectos')};
$('#fup').onsubmit=async e=>{e.preventDefault();const f=Object.fromEntries(new FormData(e.target));
 const{email,password,...data}=f;const{data:r,error}=await sb.auth.signUp({email,password,options:{data}});
 if(error)return toast(error.message);if(!r.session)toast('Cuenta creada. Revisa tu correo para confirmarla.')};
$('#out').onclick=()=>sb.auth.signOut();

// ---- Datos ----
async function load(){
 let q=sb.from('posts').select(COLS).order('created_at',{ascending:false}).limit(50);
 const t=$('#ftype').value,c=$('#fcat').value,s=$('#fq').value.replace(/[%,()*]/g,' ').trim();
 if(t)q=q.eq('type',t);if(c)q=q.eq('category',c);if(s)q=q.or(`title.ilike.%${s}%,description.ilike.%${s}%`);
 const{data,error}=await q;if(error)return toast(error.message);posts=data;
 const ids=posts.map(p=>p.id);comms=[];reacts=[];
 if(ids.length){
  [comms,reacts]=await Promise.all([
   sb.from('comments').select('id,post_id,user_id,text').in('post_id',ids).order('created_at').then(r=>r.data||[]),
   sb.from('reactions').select('target_id,type,user_id').eq('target_type','i').in('target_id',ids).then(r=>r.data||[])]);}
 const u=[...new Set([...posts,...comms].map(x=>x.user_id))];
 if(u.length)(await sb.from('public_profiles').select('id,nombre').in('id',u)).data?.forEach(p=>people[p.id]=p);
 $('#list').innerHTML=posts.map(card).join('')||'<p class="mut">Sin resultados.</p>';
}
function card(p){
 const mine=p.user_id===me.id,adm=prof?.rol==='administrador';
 const rc=k=>reacts.filter(r=>r.target_id===p.id&&r.type===k).length;
 const my=reacts.find(r=>r.target_id===p.id&&r.user_id===me.id)?.type;
 return `<article class="card" data-id="${p.id}">
 <div class="row"><span class="tag ${p.type==='Lo perdí'?'lost':'found'}">${esc(p.type)}</span><span class="st s-${esc(p.delivery_status)}">${ST[p.delivery_status]||''}</span></div>
 ${p.image_url?`<img class="ph" src="${esc(p.image_url)}" alt="" loading="lazy">`:''}
 <h3>${esc(p.title)}</h3>${p.description?`<p>${esc(p.description)}</p>`:''}
 <small>${esc(p.location||'')} · ${esc(p.category)} · ${esc(people[p.user_id]?.nombre||'—')} · ${new Date(p.created_at).toLocaleDateString('es-MX')}</small>
 <div class="row">${[['thumb','👍'],['laugh','😂'],['heart','❤️']].map(([k,e])=>`<button data-act="react" data-k="${k}" class="${my===k?'on':''}">${e} ${rc(k)}</button>`).join('')}</div>
 <div class="row"><button data-act="tel">Contactar</button><button data-act="rep">Reportar</button>
 ${mine?`<select data-act="st">${Object.entries(ST).map(([k,v])=>`<option value="${k}"${k===p.delivery_status?' selected':''}>${v}</option>`).join('')}</select>`:''}
 ${mine||adm?'<button data-act="del" class="danger">Borrar</button>':''}</div>
 <div class="cms">${comms.filter(c=>c.post_id===p.id).map(c=>`<p><b>${esc(people[c.user_id]?.nombre||'—')}</b> ${esc(c.text)}</p>`).join('')}</div>
 <form data-act="cmt"><input maxlength="1000" required placeholder="Comentar..."><button>Enviar</button></form></article>`}

// ---- Acciones (delegación de eventos) ----
const L=$('#list'),idOf=e=>+e.target.closest('.card').dataset.id;
L.onclick=async e=>{const b=e.target.closest('button[data-act]');if(!b)return;const id=idOf(e),a=b.dataset.act;
 if(a==='react')run(sb.rpc('toggle_reaction',{t:'i',tid:id,k:b.dataset.k}));
 if(a==='tel'){const{data,error}=await sb.rpc('obtener_contacto',{p_id:id});
  if(error)return toast(error.message);if(!data)return toast('El autor no dejó teléfono. Usa los comentarios.');
  const l=document.createElement('a');l.href='tel:'+data;l.textContent=data;b.replaceWith(l)}
 if(a==='rep'){const r=prompt('Motivo del reporte (mín. 3 caracteres)');if(r)run(sb.from('reports').insert({target_type:'i',target_id:id,reason:r.slice(0,500)})).then(ok=>ok&&toast('Reporte enviado'))}
 if(a==='del'&&confirm('¿Borrar esta publicación?'))run(sb.from('posts').delete().eq('id',id))};
L.onchange=e=>{if(e.target.dataset.act==='st')run(sb.from('posts').update({delivery_status:e.target.value}).eq('id',idOf(e)))};
L.onsubmit=async e=>{e.preventDefault();if(e.target.dataset.act!=='cmt')return;
 if(await run(sb.from('comments').insert({post_id:idOf(e),text:e.target.querySelector('input').value.trim()})))e.target.reset()};

// ---- Nueva publicación ----
$('#add').onclick=()=>$('#dlg').showModal();$('#cx').onclick=()=>$('#dlg').close();
$('#fnew').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target),file=f.get('file');let image_url=null;
 if(file?.size){const ext={'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[file.type];
  if(!ext||file.size>3145728)return toast('Imagen JPG/PNG/WebP de máximo 3 MB');
  const path=`${me.id}/${Date.now()}.${ext}`;const{error}=await sb.storage.from('img').upload(path,file,{contentType:file.type});
  if(error)return toast(error.message);image_url=sb.storage.from('img').getPublicUrl(path).data.publicUrl}
 const v=k=>(f.get(k)||'').trim();
 if(await run(sb.from('posts').insert({title:v('title'),description:v('description')||null,location:v('location')||null,category:v('category'),type:v('type'),tel:v('tel')||null,image_url}))){e.target.reset();$('#dlg').close()}};

// ---- Filtros y tiempo real ----
['#fq','#ftype','#fcat'].forEach(s=>$(s).oninput=()=>{clearTimeout(timer);timer=setTimeout(load,300)});
const live=()=>{clearTimeout(timer);timer=setTimeout(()=>me&&load(),500)};
sb.channel('live').on('postgres_changes',{event:'*',schema:'public',table:'posts'},live)
 .on('postgres_changes',{event:'*',schema:'public',table:'comments'},live)
 .on('postgres_changes',{event:'*',schema:'public',table:'reactions'},live).subscribe();
setInterval(()=>me&&!document.hidden&&load(),60000);
if('serviceWorker' in navigator)addEventListener('load',()=>navigator.serviceWorker.register('sw.js'));
