{* The page behind /players: who sings on which microphone right now. The
   microphone colour is what the host matches against the hardware, so it
   carries every card. Kept separate from the request page, the guests do not
   need it. *}
function BuildWebPlayersPage: RawByteString;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Add('<!doctype html>');
    S.Add('<html lang="en"><head>');
    S.Add('<meta charset="utf-8">');
    S.Add('<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">');
    S.Add('<title>UltraStar Deluxe - Players</title>');
    S.Add('<style>');
    S.Add(':root{--bg:#111420;--panel:#1b2030;--panel2:#232a3d;--line:#2e3752;--text:#e9ecf6;--dim:#98a1bb;--accent:#ffc933;--accent2:#5ad1a0;--danger:#ff7a6b;}');
    S.Add('*{box-sizing:border-box;}');
    S.Add('[hidden]{display:none !important;}');
    S.Add('html{-webkit-text-size-adjust:100%;}');
    S.Add('body{margin:0;background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;font-size:16px;}');
    // the parts the browser draws still belong to the page
    S.Add('::selection{background:var(--accent);color:#241d00;}');
    S.Add('*{scrollbar-width:thin;scrollbar-color:var(--line) transparent;}');
    S.Add('::-webkit-scrollbar{width:8px;height:8px;}');
    S.Add('::-webkit-scrollbar-thumb{background:var(--line);border-radius:4px;}');
    S.Add(':focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:4px;}');
    S.Add('input{caret-color:var(--accent);}');
    S.Add('header{background:var(--panel);border-bottom:1px solid var(--line);padding:10px 12px;}');
    S.Add('h1{margin:0;font-size:17px;}');
    S.Add('h1 span{color:var(--accent);}');
    AddMenuStyle(S);
    S.Add('.state{color:var(--dim);font-size:13px;margin-top:4px;}');
    S.Add('.state.live{color:var(--accent2);}');
    S.Add('.state.live::before{content:"";display:inline-block;width:7px;height:7px;border-radius:50%;');
    S.Add('background:var(--accent2);margin-right:7px;vertical-align:1px;}');
    S.Add('main{padding:14px 12px 28px;max-width:720px;margin:0 auto;}');

    // the microphones
    S.Add('.slots{display:grid;grid-template-columns:repeat(auto-fit,minmax(148px,1fr));gap:12px;}');
    S.Add('.slot{position:relative;background:var(--panel);border:0;border-radius:16px;padding:16px 12px 14px;');
    S.Add('display:flex;flex-direction:column;align-items:center;gap:10px;cursor:pointer;color:inherit;');
    S.Add('font:inherit;text-align:center;box-shadow:inset 0 0 0 2px var(--c),0 10px 22px -16px rgba(0,0,0,.9);');
    S.Add('transition:transform .18s cubic-bezier(.16,1,.3,1),box-shadow .18s;}');
    S.Add('.slot:hover{transform:translateY(-2px);box-shadow:inset 0 0 0 2px var(--c),0 14px 26px -16px rgba(0,0,0,1);}');
    S.Add('.slot:active{transform:translateY(0);}');
    // the colour reads as light falling on the player, not as a sticker
    S.Add('.slot::before{content:"";position:absolute;inset:0;border-radius:16px;pointer-events:none;');
    S.Add('background:radial-gradient(120% 70% at 50% 0,var(--c) 0,transparent 62%);opacity:.16;}');
    S.Add('.face{width:76px;height:76px;border-radius:50%;object-fit:cover;background:var(--panel2);');
    S.Add('border:2px solid var(--c);display:grid;place-items:center;font-size:28px;font-weight:700;');
    S.Add('color:var(--c);letter-spacing:.02em;overflow:hidden;}');
    S.Add('img.face{display:block;}');
    S.Add('.pname{font-weight:650;font-size:16px;line-height:1.25;overflow-wrap:anywhere;}');
    S.Add('.pname.unset{color:var(--dim);font-weight:500;}');
    S.Add('.mic{font-size:11px;letter-spacing:.09em;text-transform:uppercase;color:var(--dim);}');
    S.Add('.score{font-size:13px;color:var(--accent);font-weight:700;font-variant-numeric:tabular-nums;}');
    S.Add('.empty{color:var(--dim);font-size:14px;line-height:1.5;}');

    // the sheet that picks or creates a singer
    S.Add('.scrim{position:fixed;inset:0;background:rgba(8,10,18,.72);z-index:30;');
    S.Add('opacity:0;transition:opacity .2s ease;}');
    S.Add('.scrim.open{opacity:1;}');
    S.Add('.sheet{position:fixed;left:0;right:0;bottom:0;z-index:31;max-height:86vh;max-height:86dvh;overflow-y:auto;');
    S.Add('background:var(--panel);border-top:1px solid var(--line);border-radius:18px 18px 0 0;');
    S.Add('padding:16px 14px calc(16px + env(safe-area-inset-bottom));');
    S.Add('transform:translateY(14px);opacity:0;transition:transform .32s cubic-bezier(.16,1,.3,1),opacity .2s ease;}');
    S.Add('.sheet.open{transform:translateY(0);opacity:1;}');
    S.Add('@media(min-width:620px){.sheet{left:50%;right:auto;bottom:auto;top:50%;width:520px;');
    S.Add('transform:translate(-50%,-46%);border-radius:18px;border:1px solid var(--line);}');
    S.Add('.sheet.open{transform:translate(-50%,-50%);}}');
    S.Add('@media(prefers-reduced-motion:reduce){.sheet,.scrim,.slot{transition:none;}}');
    S.Add('.sheet h2{margin:0 0 2px;font-size:17px;}');
    S.Add('.sheet .for{color:var(--dim);font-size:13px;margin-bottom:14px;}');
    S.Add('.roster{list-style:none;margin:0 0 12px;padding:0;}');
    S.Add('.roster li{display:flex;align-items:center;gap:12px;padding:8px;border-radius:12px;}');
    S.Add('.roster li+li{margin-top:4px;}');
    S.Add('.pick{flex:1;display:flex;align-items:center;gap:12px;background:none;border:0;color:inherit;');
    S.Add('font:inherit;text-align:left;padding:4px;cursor:pointer;border-radius:10px;min-width:0;}');
    S.Add('.pick:hover{background:var(--panel2);}');
    S.Add('.thumb{width:44px;height:44px;border-radius:50%;flex:none;object-fit:cover;background:var(--panel2);');
    S.Add('display:grid;place-items:center;font-weight:700;color:var(--dim);border:1px solid var(--line);overflow:hidden;}');
    S.Add('img.thumb{display:block;}');
    S.Add('.pick .nm{font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}');
    S.Add('.pick[aria-current] .nm{color:var(--accent);}');
    S.Add('.tick{margin-left:auto;flex:none;color:var(--accent);opacity:0;}');
    S.Add('.pick[aria-current] .tick{opacity:1;}');
    S.Add('button{background:var(--panel2);color:var(--text);border:1px solid var(--line);border-radius:11px;');
    S.Add('padding:11px 14px;font-size:15px;font-family:inherit;cursor:pointer;}');
    S.Add('button:disabled{opacity:.45;cursor:default;}');
    S.Add('.icon{flex:none;width:40px;height:40px;padding:0;display:grid;place-items:center;color:var(--dim);background:none;border-color:transparent;}');
    S.Add('.icon:hover{color:var(--danger);border-color:var(--line);background:var(--panel2);}');
    S.Add('.primary{background:var(--accent);border-color:var(--accent);color:#241d00;font-weight:700;}');
    S.Add('.wide{width:100%;display:flex;align-items:center;justify-content:center;gap:8px;}');
    S.Add('.ghost{border-style:dashed;color:var(--dim);}');

    // the create form
    S.Add('.shoot{display:flex;flex-direction:column;align-items:center;gap:6px;margin:6px 0 16px;}');
    S.Add('.shoot input{position:absolute;width:1px;height:1px;opacity:0;}');
    S.Add('.drop{width:112px;height:112px;border-radius:50%;background:var(--panel2);border:2px dashed var(--line);');
    S.Add('display:grid;place-items:center;color:var(--dim);cursor:pointer;overflow:hidden;}');
    S.Add('.drop:hover{border-color:var(--accent);color:var(--accent);}');
    S.Add('.drop img{width:100%;height:100%;object-fit:cover;}');
    S.Add('.hint{color:var(--dim);font-size:12px;}');
    S.Add('label.field{display:block;font-size:12px;letter-spacing:.07em;text-transform:uppercase;color:var(--dim);margin-bottom:6px;}');
    S.Add('input[type=text]{width:100%;background:var(--panel2);border:1px solid var(--line);border-radius:11px;');
    S.Add('color:var(--text);padding:12px;font-size:16px;font-family:inherit;}');
    S.Add('.row{display:flex;gap:8px;margin-top:16px;}');
    S.Add('.row button{flex:1;}');
    S.Add('.toast{position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:var(--accent2);');
    S.Add('color:#04281c;padding:10px 16px;border-radius:20px;font-weight:600;font-size:14px;opacity:0;');
    S.Add('pointer-events:none;transition:opacity .2s;z-index:40;}');
    S.Add('.toast.show{opacity:1;}');
    S.Add('</style>');
    S.Add('</head><body>');

    S.Add('<header>');
    AddMenuNav(S, '/players', 'Players');
    S.Add('<div class="state" id="state">Looking for the game...</div>');
    S.Add('</header>');

    S.Add('<main>');
    S.Add('<div class="slots" id="slots"></div>');
    S.Add('<div class="empty" id="empty" hidden>No microphones yet.<br>');
    S.Add('Start a song once, then the players show up here.</div>');
    S.Add('</main>');

    S.Add('<div class="scrim" id="scrim" hidden></div>');
    S.Add('<section class="sheet" id="sheet" hidden aria-modal="true" role="dialog" aria-labelledby="sheetTitle"></section>');
    S.Add('<div class="toast" id="toast"></div>');

    S.Add('<script>');
    S.Add('var elSlots=document.getElementById("slots");');
    S.Add('var elState=document.getElementById("state");');
    S.Add('var elEmpty=document.getElementById("empty");');
    S.Add('var elScrim=document.getElementById("scrim");');
    S.Add('var elSheet=document.getElementById("sheet");');
    S.Add('var elToast=document.getElementById("toast");');
    S.Add('var players=[];var roster=[];var slot=-1;var photo="";');

    // one stroke weight for every icon on the page
    S.Add('function svg(path,size){return ''<svg viewBox="0 0 24 24" width="''+(size||20)+''" height="''+(size||20)+''" ''+');
    S.Add('''fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">''+path+''</svg>'';}');
    S.Add('var ICON_TRASH=svg(''<path d="M4 7h16M9 7V5h6v2M7 7l1 12h8l1-12"/>'');');
    S.Add('var ICON_PLUS=svg(''<path d="M12 5v14M5 12h14"/>'');');
    S.Add('var ICON_CHECK=svg(''<path d="M4 12.5 9.5 18 20 7"/>'');');
    S.Add('var ICON_EDIT=svg(''<path d="M4 20h4L19 9a2.1 2.1 0 0 0-3-3L5 17z"/>'');');
    S.Add('var ICON_CAMERA=svg(''<path d="M3 8.5A1.5 1.5 0 0 1 4.5 7h2L8 5h8l1.5 2h2A1.5 1.5 0 0 1 21 8.5v9A1.5 1.5 0 0 1 19.5 19h-15A1.5 1.5 0 0 1 3 17.5z"/><circle cx="12" cy="12.8" r="3.4"/>'',30);');

    S.Add('function toast(m){elToast.textContent=m;elToast.classList.add("show");');
    S.Add('clearTimeout(toast.t);toast.t=setTimeout(function(){elToast.classList.remove("show");},1800);}');
    S.Add('function post(url,data){');
    S.Add('var body=Object.keys(data).map(function(k){return encodeURIComponent(k)+"="+encodeURIComponent(data[k]);}).join("&");');
    S.Add('return fetch(url,{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:body})');
    S.Add('.then(function(r){return r.json();});}');
    S.Add('function initial(name){return (name||"?").trim().charAt(0).toUpperCase();}');

    // ---- the microphones
    S.Add('function slotCard(p,i){');
    S.Add('var b=document.createElement("button");b.className="slot";b.style.setProperty("--c",p.rgb);');
    S.Add('b.setAttribute("aria-label","Change who sings on microphone "+(i+1));');
    S.Add('var face;');
    S.Add('if(p.photo){face=document.createElement("img");face.src="/api/roster/photo?id="+p.photo;face.alt="";');
    // a photo that was deleted while it was worn falls back to the letter
    S.Add('face.onerror=function(){var d=document.createElement("div");d.className="face";');
    S.Add('d.textContent=initial(p.name);face.replaceWith(d);};}');
    S.Add('else{face=document.createElement("div");face.textContent=initial(p.name);}');
    S.Add('face.className="face";b.appendChild(face);');
    S.Add('var n=document.createElement("div");n.className="pname";');
    S.Add('if(p.name){n.textContent=p.name;}else{n.textContent="Tap to set";n.className+=" unset";}');
    S.Add('b.appendChild(n);');
    S.Add('var m=document.createElement("div");m.className="mic";');
    S.Add('m.textContent=p.color?p.color+" mic":"Microphone "+(i+1);b.appendChild(m);');
    S.Add('var sc=document.createElement("div");sc.className="score";sc.textContent=p.score;b.appendChild(sc);');
    S.Add('b.onclick=function(){openRoster(i);};');
    S.Add('return b;}');

    // ---- the sheet: pick somebody
    S.Add('function openRoster(i){');
    S.Add('slot=i;');
    S.Add('fetch("/api/roster").then(function(r){return r.json();}).then(function(d){');
    S.Add('roster=d.players;drawRoster();showSheet();}).catch(function(){toast("Connection lost");});}');

    S.Add('function drawRoster(){');
    S.Add('var p=players[slot]||{};');
    S.Add('elSheet.innerHTML="";');
    S.Add('var h=document.createElement("h2");h.id="sheetTitle";h.textContent="Who is on this microphone?";');
    S.Add('var f=document.createElement("div");f.className="for";');
    S.Add('f.textContent=(p.color?p.color+" microphone":"Microphone "+(slot+1))+(p.name?" · now "+p.name:"");');
    S.Add('elSheet.appendChild(h);elSheet.appendChild(f);');

    S.Add('var ul=document.createElement("ul");ul.className="roster";');
    S.Add('roster.forEach(function(r){');
    S.Add('var li=document.createElement("li");');
    S.Add('var pick=document.createElement("button");pick.className="pick";');
    S.Add('if(r.name===p.name){pick.setAttribute("aria-current","true");}');
    S.Add('var th;');
    S.Add('if(r.photo){th=document.createElement("img");th.src="/api/roster/photo?id="+r.id;th.alt="";}');
    S.Add('else{th=document.createElement("div");th.textContent=initial(r.name);}');
    S.Add('th.className="thumb";pick.appendChild(th);');
    S.Add('var nm=document.createElement("span");nm.className="nm";nm.textContent=r.name;pick.appendChild(nm);');
    S.Add('var tk=document.createElement("span");tk.className="tick";tk.innerHTML=ICON_CHECK;pick.appendChild(tk);');
    S.Add('pick.onclick=function(){assign(r);};');
    S.Add('var ed=document.createElement("button");ed.className="icon";ed.innerHTML=ICON_EDIT;');
    S.Add('ed.setAttribute("aria-label","Edit "+r.name);');
    S.Add('ed.onclick=function(){drawForm(r);};');
    S.Add('var del=document.createElement("button");del.className="icon";del.innerHTML=ICON_TRASH;');
    S.Add('del.setAttribute("aria-label","Delete "+r.name);');
    S.Add('del.onclick=function(){remove(r);};');
    S.Add('li.appendChild(pick);li.appendChild(ed);li.appendChild(del);ul.appendChild(li);});');
    S.Add('elSheet.appendChild(ul);');

    S.Add('if(!roster.length){var e=document.createElement("div");e.className="empty";');
    S.Add('e.style.margin="4px 0 14px";e.textContent="Nobody saved yet. Add the first singer.";elSheet.appendChild(e);}');

    S.Add('var add=document.createElement("button");add.className="wide ghost";');
    S.Add('add.innerHTML=ICON_PLUS+"<span>Add someone</span>";');
    S.Add('add.onclick=function(){drawForm(null);};elSheet.appendChild(add);');
    S.Add('var row=document.createElement("div");row.className="row";');
    S.Add('var cancel=document.createElement("button");cancel.textContent="Close";cancel.onclick=hideSheet;');
    S.Add('row.appendChild(cancel);elSheet.appendChild(row);}');

    // ---- the sheet: create somebody
    S.Add('function drawForm(edit){');
    S.Add('photo="";');
    S.Add('elSheet.innerHTML="";');
    S.Add('var h=document.createElement("h2");h.id="sheetTitle";');
    S.Add('h.textContent=edit?"Edit "+edit.name:"New singer";');
    S.Add('var f=document.createElement("div");f.className="for";');
    S.Add('f.textContent=edit?"A new photo is used right away.":"Saved for the next party as well.";');
    S.Add('elSheet.appendChild(h);elSheet.appendChild(f);');

    S.Add('var shoot=document.createElement("label");shoot.className="shoot";');
    S.Add('var drop=document.createElement("span");drop.className="drop";drop.innerHTML=ICON_CAMERA;');
    S.Add('var file=document.createElement("input");file.type="file";file.accept="image/*";');
    S.Add('var hint=document.createElement("span");hint.className="hint";');
    S.Add('hint.textContent=edit?"Tap to change the photo":"Photo, optional";');
    S.Add('if(edit&&edit.photo){var cur=new Image();');
    S.Add('cur.src="/api/roster/photo?id="+edit.id+"&t="+Date.now();');
    S.Add('drop.innerHTML="";drop.appendChild(cur);}');
    S.Add('file.onchange=function(){pickPhoto(file,drop,hint);};');
    S.Add('shoot.appendChild(drop);shoot.appendChild(file);shoot.appendChild(hint);');
    S.Add('elSheet.appendChild(shoot);');

    S.Add('var lab=document.createElement("label");lab.className="field";lab.textContent="Name";');
    S.Add('lab.setAttribute("for","singerfield");elSheet.appendChild(lab);');
    S.Add('var inp=document.createElement("input");inp.type="text";inp.id="singerfield";');
    S.Add('inp.name="singerfield";inp.maxLength=40;');
    S.Add('if(edit){inp.value=edit.name;}');
    // a stage name is not an address, and the autofill bar covered the buttons
    S.Add('inp.autocomplete="off";inp.autocapitalize="words";inp.spellcheck=false;');
    S.Add('inp.enterKeyHint="done";elSheet.appendChild(inp);');
    S.Add('inp.onkeydown=function(e){if(e.key==="Enter"){save(inp,null,edit);}};');
    S.Add('inp.onfocus=function(){setTimeout(function(){fitSheet();');
    S.Add('row.scrollIntoView({block:"end",behavior:"smooth"});},250);};');

    S.Add('var row=document.createElement("div");row.className="row";');
    S.Add('var back=document.createElement("button");back.textContent="Back";');
    S.Add('back.onclick=function(){drawRoster();};');
    S.Add('var ok=document.createElement("button");ok.className="primary";ok.textContent="Save";');
    S.Add('ok.onclick=function(){save(inp,ok,edit);};');
    S.Add('row.appendChild(back);row.appendChild(ok);elSheet.appendChild(row);');
    S.Add('inp.focus();}');

    // a party photo is a snapshot, 256px is all the game ever shows
    S.Add('function pickPhoto(file,drop,hint){');
    S.Add('var f=file.files&&file.files[0];if(!f){return;}');
    S.Add('var img=new Image();');
    S.Add('img.onload=function(){');
    S.Add('var c=document.createElement("canvas");c.width=256;c.height=256;');
    S.Add('var s=Math.min(img.width,img.height);');
    S.Add('c.getContext("2d").drawImage(img,(img.width-s)/2,(img.height-s)/2,s,s,0,0,256,256);');
    S.Add('var url=c.toDataURL("image/jpeg",0.82);');
    S.Add('photo=url.slice(url.indexOf(",")+1);');
    S.Add('drop.innerHTML="";var prev=new Image();prev.src=url;drop.appendChild(prev);');
    S.Add('hint.textContent="Tap the photo to change it";');
    S.Add('URL.revokeObjectURL(img.src);};');
    S.Add('img.onerror=function(){toast("That file is not an image");};');
    S.Add('img.src=URL.createObjectURL(f);}');

    S.Add('function save(inp,ok,edit){');
    S.Add('var name=inp.value.trim();');
    S.Add('if(!name){inp.focus();toast("A name is needed");return;}');
    S.Add('if(ok){ok.disabled=true;ok.textContent="Saving...";}');
    S.Add('function failed(){toast("Could not save");if(ok){ok.disabled=false;ok.textContent="Save";}}');
    S.Add('if(edit){');
    S.Add('post("/api/roster/update",{id:edit.id,name:name,photo:photo}).then(function(res){');
    S.Add('if(!res.ok){failed();return;}');
    S.Add('toast(name+" updated");openRoster(slot);load();');
    S.Add('}).catch(failed);return;}');
    S.Add('post("/api/roster/add",{name:name,photo:photo}).then(function(res){');
    S.Add('if(!res.id){failed();return;}');
    S.Add('assign({id:res.id,name:name});');
    S.Add('}).catch(failed);}');

    S.Add('function assign(r){');
    S.Add('post("/api/roster/assign",{p:slot,id:r.id}).then(function(res){');
    S.Add('if(res.ok){toast(r.name+" is on the "+((players[slot]||{}).color||"")+" microphone");hideSheet();load();}');
    S.Add('else{toast("Could not change the microphone");}');
    S.Add('}).catch(function(){toast("Connection lost");});}');

    S.Add('function remove(r){');
    S.Add('post("/api/roster/delete",{id:r.id}).then(function(){');
    S.Add('roster=roster.filter(function(x){return x.id!==r.id;});drawRoster();toast(r.name+" removed");');
    S.Add('}).catch(function(){toast("Connection lost");});}');

    // the on screen keyboard shrinks the visible viewport but not the layout
    // one, so the sheet would end up behind it
    S.Add('function fitSheet(){');
    S.Add('var v=window.visualViewport;');
    S.Add('if(!v||window.innerWidth>=620){elSheet.style.bottom="";elSheet.style.maxHeight="";return;}');
    S.Add('elSheet.style.bottom=Math.max(0,window.innerHeight-v.height-v.offsetTop)+"px";');
    S.Add('elSheet.style.maxHeight=(v.height-12)+"px";}');
    S.Add('if(window.visualViewport){');
    S.Add('visualViewport.addEventListener("resize",fitSheet);');
    S.Add('visualViewport.addEventListener("scroll",fitSheet);}');

    S.Add('function showSheet(){elScrim.hidden=false;elSheet.hidden=false;fitSheet();');
    S.Add('requestAnimationFrame(function(){elScrim.classList.add("open");elSheet.classList.add("open");});}');
    S.Add('function hideSheet(){elScrim.classList.remove("open");elSheet.classList.remove("open");');
    S.Add('setTimeout(function(){elScrim.hidden=true;elSheet.hidden=true;},220);}');
    S.Add('elScrim.onclick=hideSheet;');
    S.Add('document.addEventListener("keydown",function(e){if(e.key==="Escape"&&!elSheet.hidden){hideSheet();}});');

    S.Add('function load(){');
    S.Add('fetch("/api/players").then(function(r){return r.json();}).then(function(data){');
    S.Add('elState.textContent=data.singing?"A song is running - a change counts for it":');
    S.Add('"No song running - a change counts for the next one";');
    S.Add('elState.classList.toggle("live",!!data.singing);');
    S.Add('players=data.players;');
    S.Add('elEmpty.hidden=players.length>0;');
    S.Add('elSlots.innerHTML="";');
    S.Add('players.forEach(function(p,i){elSlots.appendChild(slotCard(p,i));});');
    S.Add('}).catch(function(){elState.textContent="The game cannot be reached";});}');
    S.Add('load();setInterval(function(){if(elSheet.hidden){load();}},2500);');
    S.Add('</script>');
    S.Add('</body></html>');

    Result := S.Text;
  finally
    S.Free;
  end;
end;
