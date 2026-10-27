{* The title of every page doubles as the menu to the other pages. It is a
   <details> element, so the popover needs no script at all. *}

procedure AddMenuStyle(S: TStringList);
begin
  S.Add('.nav{position:relative;}');
  S.Add('.nav summary{list-style:none;cursor:pointer;display:inline-block;}');
  S.Add('.nav summary::-webkit-details-marker{display:none;}');
  S.Add('.nav summary h1{display:inline;}');
  S.Add('.nav summary::after{content:" \25be";color:var(--dim);}');
  S.Add('.nav[open] summary::after{content:" \25b4";}');
  S.Add('.nav menu{position:absolute;left:0;top:100%;margin:6px 0 0;padding:6px;z-index:20;');
  S.Add('background:var(--panel2);border:1px solid var(--line);border-radius:10px;');
  S.Add('list-style:none;min-width:190px;box-shadow:0 8px 24px rgba(0,0,0,.45);}');
  S.Add('.nav a{display:block;padding:9px 10px;border-radius:7px;color:var(--text);');
  S.Add('text-decoration:none;font-size:15px;}');
  S.Add('.nav a[aria-current]{color:var(--accent);font-weight:700;}');
  S.Add('.nav a:hover{background:var(--panel);}');
end;

{* Active is the path of the page this menu is built into. *}
procedure AddMenuNav(S: TStringList; const Active, Suffix: UTF8String);

  procedure Entry(const Path, Caption: UTF8String);
  begin
    S.Add('<li><a href="' + Path + '"' +
          IfThen(Path = Active, ' aria-current="page"', '') + '>' + Caption + '</a></li>');
  end;

begin
  S.Add('<details class="nav">');
  S.Add('<summary><h1>UltraStar <span>Deluxe</span>' +
        IfThen(Suffix <> '', ' &middot; ' + Suffix, '') + '</h1></summary>');
  S.Add('<menu>');
  Entry('/', 'Song requests');
  Entry('/players', 'Players');
  Entry('/wuensche', 'Song wishes');
  Entry('/broken', 'Broken songs');
  Entry('/videos', 'Unused videos');
  S.Add('</menu>');
  S.Add('</details>');
end;
