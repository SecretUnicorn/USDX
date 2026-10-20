{* The page behind /wuensche: the songs guests asked for that are not in the
   collection. The list comes straight from song-requests.txt. *}
function BuildWebWishesPage: RawByteString;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Add('<!doctype html>');
    S.Add('<html lang="en"><head>');
    S.Add('<meta charset="utf-8">');
    S.Add('<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">');
    S.Add('<title>UltraStar Deluxe - Song wishes</title>');
    S.Add('<style>');
    S.Add(':root{--bg:#111420;--panel:#1b2030;--panel2:#232a3d;--line:#2e3752;--text:#e9ecf6;--dim:#98a1bb;--accent:#ffc933;--accent2:#5ad1a0;}');
    S.Add('*{box-sizing:border-box;}');
    S.Add('[hidden]{display:none !important;}');
    S.Add('body{margin:0;background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;font-size:16px;}');
    S.Add('header{background:var(--panel);border-bottom:1px solid var(--line);padding:10px 12px;}');
    S.Add('h1{margin:0;font-size:17px;}');
    S.Add('h1 span{color:var(--accent);}');
    AddMenuStyle(S);
    S.Add('main{padding:12px;max-width:620px;margin:0 auto;}');
    S.Add('ul{list-style:none;margin:0;padding:0;}');
    S.Add('li{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:10px;margin-bottom:8px;}');
    S.Add('.wish{font-weight:600;}');
    S.Add('.by{color:var(--dim);font-size:13px;margin-top:3px;}');
    S.Add('.count{color:var(--dim);font-size:13px;margin-bottom:8px;}');
    S.Add('.empty{color:var(--dim);font-size:14px;}');
    S.Add('</style>');
    S.Add('</head><body>');
    S.Add('<header>');
    AddMenuNav(S, '/wuensche', 'Song wishes');
    S.Add('</header>');
    S.Add('<main>');
    S.Add('<div class="count" id="count"></div>');
    S.Add('<ul id="wishes"></ul>');
    S.Add('<div class="empty" id="empty" hidden>Nothing yet. A song that the search does not find can be requested on the song page.</div>');
    S.Add('</main>');
    S.Add('<script>');
    S.Add('var elList=document.getElementById("wishes");');
    S.Add('var elCount=document.getElementById("count");');
    S.Add('var elEmpty=document.getElementById("empty");');
    S.Add('function load(){');
    S.Add('fetch("/api/wishes").then(function(r){return r.text();}).then(function(text){');
    S.Add('var lines=text.split("\n").filter(function(l){return l.trim().length>0;});');
    S.Add('elList.innerHTML="";');
    S.Add('elEmpty.hidden=lines.length>0;');
    S.Add('elCount.textContent=lines.length===1?"1 wish":lines.length+" wishes";');
    // newest first, that is what you want to read out after a party
    S.Add('lines.reverse().forEach(function(line){');
    S.Add('var f=line.split("\t");');
    S.Add('var li=document.createElement("li");');
    S.Add('var w=document.createElement("div");w.className="wish";w.textContent=f[2]||line;');
    S.Add('var by=document.createElement("div");by.className="by";');
    S.Add('by.textContent=(f[1]&&f[1]!=="-"?f[1]+" · ":"")+(f[0]||"");');
    S.Add('li.appendChild(w);li.appendChild(by);elList.appendChild(li);});');
    S.Add('}).catch(function(){});}');
    S.Add('load();setInterval(load,5000);');
    S.Add('</script>');
    S.Add('</body></html>');

    Result := S.Text;
  finally
    S.Free;
  end;
end;
