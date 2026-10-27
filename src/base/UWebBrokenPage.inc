{* The page behind /broken: song folders the game refused to load. They are
   invisible everywhere else - not in the song list, not in the search, and
   the Syncer believes it has them - so this is the only place they can be
   seen and thrown away. *}
function BuildWebBrokenPage: RawByteString;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Add('<!doctype html>');
    S.Add('<html lang="en"><head>');
    S.Add('<meta charset="utf-8">');
    S.Add('<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">');
    S.Add('<title>UltraStar Deluxe - Broken songs</title>');
    S.Add('<style>');
    S.Add(':root{--bg:#111420;--panel:#1b2030;--panel2:#232a3d;--line:#2e3752;--text:#e9ecf6;--dim:#98a1bb;--accent:#ffc933;--accent2:#5ad1a0;--danger:#ff7a6b;}');
    S.Add('*{box-sizing:border-box;}');
    S.Add('[hidden]{display:none !important;}');
    S.Add('body{margin:0;background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;font-size:16px;}');
    S.Add('header{background:var(--panel);border-bottom:1px solid var(--line);padding:10px 12px;}');
    S.Add('h1{margin:0;font-size:17px;}');
    S.Add('h1 span{color:var(--accent);}');
    AddMenuStyle(S);
    S.Add('main{padding:12px;max-width:680px;margin:0 auto;}');
    S.Add('ul{list-style:none;margin:0;padding:0;}');
    S.Add('li{background:var(--panel);border:1px solid var(--line);border-radius:10px;');
    S.Add('padding:10px;margin-bottom:8px;display:flex;gap:10px;align-items:flex-start;}');
    S.Add('.meta{flex:1;min-width:0;}');
    S.Add('.folder{font-weight:600;overflow-wrap:anywhere;}');
    S.Add('.why{color:var(--danger);font-size:13px;margin-top:3px;}');
    S.Add('.why.keep{color:var(--accent);}');
    S.Add('.where{color:var(--dim);font-size:12px;margin-top:3px;overflow-wrap:anywhere;}');
    S.Add('.count{color:var(--dim);font-size:13px;margin-bottom:8px;}');
    S.Add('.empty{color:var(--dim);font-size:14px;line-height:1.5;}');
    S.Add('button{flex:none;background:var(--panel2);border:1px solid var(--danger);color:var(--danger);');
    S.Add('font-weight:700;font-size:13px;border-radius:9px;padding:9px 12px;cursor:pointer;}');
    S.Add('button:disabled{opacity:.5;cursor:default;}');
    S.Add(':focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:4px;}');
    S.Add('.hint{color:var(--dim);font-size:13px;line-height:1.5;margin-top:14px;}');
    S.Add('</style>');
    S.Add('</head><body>');
    S.Add('<header>');
    AddMenuNav(S, '/broken', 'Broken songs');
    S.Add('</header>');
    S.Add('<main>');
    S.Add('<div class="count" id="count"></div>');
    S.Add('<ul id="list"></ul>');
    S.Add('<div class="empty" id="empty" hidden>Nothing broken. Every song file in your folders loaded.</div>');
    S.Add('<div class="hint" id="hint" hidden>Deleting removes the whole folder from the disk. ');
    S.Add('The Syncer then offers the song again, because it only hides what it still finds there.</div>');
    S.Add('</main>');
    S.Add('<script>');
    S.Add('var elList=document.getElementById("list");');
    S.Add('var elCount=document.getElementById("count");');
    S.Add('var elEmpty=document.getElementById("empty");');
    S.Add('var elHint=document.getElementById("hint");');
    // the folder is what the host recognises, the full path is for certainty
    S.Add('function folderOf(p){var f=p.split("/");f.pop();return f.pop()||p;}');
    // a song file without a folder of its own can only be deleted by itself
    S.Add('function nameOf(x){return x.loose?x.path.split("/").pop():folderOf(x.path);}');
    S.Add('function row(x){');
    S.Add('var li=document.createElement("li");');
    S.Add('var meta=document.createElement("div");meta.className="meta";');
    S.Add('var n=document.createElement("div");n.className="folder";n.textContent=nameOf(x);');
    S.Add('var w=document.createElement("div");w.className="why";w.textContent=x.problem;');
    // an audio file in the folder means one missing line, not a lost download
    S.Add('if(x.audio){w.className="why keep";');
    S.Add('w.textContent="The audio file "+x.audio+" is right there - only the #MP3 line is '
          + 'missing from the txt. Adding it rescues the song.";}');
    S.Add('var p=document.createElement("div");p.className="where";p.textContent=x.path;');
    S.Add('meta.appendChild(n);meta.appendChild(w);meta.appendChild(p);');
    S.Add('var b=document.createElement("button");b.textContent="Delete";');
    S.Add('b.onclick=function(){');
    S.Add('var warn=x.audio&&!x.loose?"\n\nIt contains the audio file "+x.audio+".":"";');
    S.Add('var what=x.loose?"Delete the file":"Delete the whole folder";');
    S.Add('if(!confirm(what+"\n\n"+nameOf(x)+warn+"\n\nThis cannot be undone.")){return;}');
    S.Add('b.disabled=true;b.textContent="Deleting...";');
    S.Add('fetch("/api/broken/delete",{method:"POST",');
    S.Add('headers:{"Content-Type":"application/x-www-form-urlencoded"},');
    S.Add('body:"path="+encodeURIComponent(x.path)})');
    S.Add('.then(function(r){return r.json();}).then(function(d){');
    S.Add('if(d.error){b.disabled=false;b.textContent="Delete";alert(d.error);return;}');
    S.Add('load();}).catch(function(){b.disabled=false;b.textContent="Delete";});};');
    S.Add('li.appendChild(meta);li.appendChild(b);return li;}');
    S.Add('function load(){');
    S.Add('fetch("/api/broken").then(function(r){return r.json();}).then(function(d){');
    S.Add('var songs=d.songs||[];');
    S.Add('elList.innerHTML="";');
    S.Add('songs.forEach(function(x){elList.appendChild(row(x));});');
    S.Add('elEmpty.hidden=songs.length>0;');
    S.Add('elHint.hidden=songs.length===0;');
    S.Add('elCount.textContent=songs.length===1?"1 song the game refused":songs.length+" songs the game refused";');
    S.Add('}).catch(function(){});}');
    S.Add('load();');
    S.Add('</script>');
    S.Add('</body></html>');

    Result := S.Text;
  finally
    S.Free;
  end;
end;
