import os
from pathlib import Path
from flask import Flask, request, abort, send_from_directory, jsonify, make_response, redirect
from werkzeug.utils import secure_filename
import mimetypes

TOKEN = os.environ["CLIP_TOKEN"]
DATA = Path("/var/lib/clip")
TEXT_FILE = DATA / "clip.txt"
FILES_DIR = DATA / "files"
MAX_MB = 64

SAFE_INLINE_MIME = {
    "image/png", "image/jpeg", "image/gif", "image/webp",
    "application/pdf",
    "audio/mpeg", "audio/ogg", "audio/wav",
    "video/mp4", "video/webm",
}

DATA.mkdir(parents=True, exist_ok=True)
FILES_DIR.mkdir(parents=True, exist_ok=True)
TEXT_FILE.touch()

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_MB * 1024 * 1024


def authed():
    return (request.cookies.get("token") == TOKEN
            or request.headers.get("X-Token") == TOKEN
            or request.args.get("t") == TOKEN
            or request.form.get("token") == TOKEN)


def need_auth():
    if not authed():
        abort(403)


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>clip</title>
<style>
:root{--bg:#0f1115;--panel:#161a22;--panel2:#1d222c;--border:#2a313d;
      --fg:#e6e8ec;--muted:#8b93a3;--accent:#5b9dff;--ok:#4ade80;--bad:#f87171}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
     font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
.wrap{max-width:780px;margin:0 auto;padding:24px 16px 60px}
header{display:flex;align-items:center;justify-content:space-between;margin-bottom:20px}
h1{margin:0;font-size:18px;font-weight:600;letter-spacing:.3px}
h1 .dot{display:inline-block;width:8px;height:8px;border-radius:50%;
        background:var(--ok);margin-right:8px;vertical-align:middle}
.muted{color:var(--muted);font-size:12px}
section{background:var(--panel);border:1px solid var(--border);
        border-radius:10px;padding:16px;margin-bottom:16px}
section h2{margin:0 0 10px;font-size:13px;font-weight:500;
           text-transform:uppercase;letter-spacing:.6px;color:var(--muted)}
textarea{width:100%;min-height:160px;background:var(--panel2);color:var(--fg);
         border:1px solid var(--border);border-radius:8px;padding:12px;
         font:13px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace;resize:vertical}
textarea:focus{outline:none;border-color:var(--accent)}
.row{display:flex;gap:8px;align-items:center;margin-top:10px}
button,.btn{background:var(--panel2);color:var(--fg);border:1px solid var(--border);
            border-radius:8px;padding:8px 14px;font:inherit;cursor:pointer}
button:hover,.btn:hover{border-color:var(--accent)}
button.primary{background:var(--accent);border-color:var(--accent);color:#0a1220}
.status{font-size:12px;color:var(--muted);margin-left:auto}
.status.ok{color:var(--ok)} .status.bad{color:var(--bad)}
#drop{border:2px dashed var(--border);border-radius:10px;padding:28px;
      text-align:center;color:var(--muted);transition:.15s;cursor:pointer}
#drop.over{border-color:var(--accent);background:rgba(91,157,255,.06);color:var(--fg)}
#drop input{display:none}
ul.files{list-style:none;margin:0;padding:0}
ul.files li{display:flex;align-items:center;gap:10px;padding:10px 12px;
            background:var(--panel2);border:1px solid var(--border);
            border-radius:8px;margin-bottom:6px}
ul.files .name{flex:1;font-family:ui-monospace,monospace;font-size:13px;
               overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
ul.files .size{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}
ul.files .size,ul.files .date{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}
ul.files .date{min-width:96px;text-align:right}
ul.files a,ul.files button{padding:4px 10px;font-size:12px}
.empty{color:var(--muted);font-size:13px;padding:8px 0}
.login{max-width:360px;margin:80px auto;padding:24px;background:var(--panel);
       border:1px solid var(--border);border-radius:10px}
.login input{width:100%;background:var(--panel2);color:var(--fg);
             border:1px solid var(--border);border-radius:8px;padding:10px;
             font:inherit;margin-bottom:10px}
.login button{width:100%}
</style></head><body>
<div class="wrap">
<header>
  <h1><span class="dot"></span>clip</h1>
  <span class="muted" id="meta">__META__</span>
</header>

<section>
  <h2>text</h2>
  <textarea id="txt" placeholder="paste a link, snippet, anything…">__TEXT__</textarea>
  <div class="row">
    <button class="primary" onclick="saveText()">save</button>
    <button onclick="copyText()">copy</button>
    <button onclick="clearText()">clear</button>
    <span class="status" id="ts">auto-save: idle</span>
  </div>
</section>

<section>
  <h2>files</h2>
  <label id="drop">
    <input type="file" id="fi" multiple>
    <div><strong>Drop files here</strong> or click to choose</div>
    <div class="muted" style="margin-top:6px">max __MAX__MB per file</div>
  </label>
  <div id="prog" class="muted" style="margin-top:10px;display:none"></div>
  <ul class="files" id="list" style="margin-top:14px"></ul>
</section>
</div>

<script>
const $=s=>document.querySelector(s);
const txt=$("#txt"),ts=$("#ts"),drop=$("#drop"),fi=$("#fi"),list=$("#list"),prog=$("#prog");

let saveT;
txt.addEventListener("input",()=>{
  ts.textContent="auto-save: typing…";ts.className="status";
  clearTimeout(saveT);saveT=setTimeout(saveText,600);
});

async function saveText(){
  ts.textContent="saving…";
  const fd=new FormData();fd.append("text",txt.value);
  const r=await fetch("/save",{method:"POST",body:fd});
  if(r.ok){ts.textContent="saved";ts.className="status ok";
           setTimeout(()=>ts.textContent="auto-save: idle",1500);}
  else{ts.textContent="error";ts.className="status bad"}
}
async function copyText(){
  try{await navigator.clipboard.writeText(txt.value);
      ts.textContent="copied";ts.className="status ok";
      setTimeout(()=>ts.textContent="auto-save: idle",1200);}
  catch(e){ts.textContent="copy blocked";ts.className="status bad"}
}
function clearText(){txt.value="";saveText()}

function fmt(n){const u=["B","KB","MB","GB"];let i=0;while(n>=1024&&i<3){n/=1024;i++}
                return n.toFixed(n<10&&i?1:0)+" "+u[i]}


function fmtDate(ts){
  const d=new Date(ts*1000), now=new Date();
  const sameDay = d.toDateString()===now.toDateString();
  const pad=n=>String(n).padStart(2,'0');
  const hm=`${pad(d.getHours())}:${pad(d.getMinutes())}`;
  if(sameDay) return `today ${hm}`;
  const yest=new Date(now); yest.setDate(now.getDate()-1);
  if(d.toDateString()===yest.toDateString()) return `yesterday ${hm}`;
  const mon=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.getMonth()];
  const sameYear = d.getFullYear()===now.getFullYear();
  return sameYear ? `${mon} ${d.getDate()} ${hm}`
                  : `${mon} ${d.getDate()} ${d.getFullYear()}`;
}

async function loadFiles(){
  const r=await fetch("/files");if(!r.ok)return;
  const a=await r.json();
  if(!a.length){list.innerHTML='<div class="empty">no files</div>';return}
  list.innerHTML=a.map(f=>{
    const u=encodeURIComponent(f.name);
    const safe=f.name.replace(/'/g,"\\'");
    return `<li>
      <a class="name" href="/file/${u}?inline=1" target="_blank" rel="noopener" title="${f.name}">${f.name}</a>
      <span class="date">${fmtDate(f.mtime)}</span>
      <span class="size">${fmt(f.size)}</span>
      <a class="btn" href="/file/${u}?inline=1" target="_blank" rel="noopener">view</a>
      <a class="btn" href="/file/${u}" download>download</a>
      <button onclick="delFile('${safe}')">delete</button></li>`;
  }).join("");
}


async function delFile(name){
  if(!confirm("delete "+name+"?"))return;
  await fetch("/file/"+encodeURIComponent(name),{method:"DELETE"});
  loadFiles();
}
async function upload(files){
  for(const f of files){
    prog.style.display="block";prog.textContent=`uploading ${f.name}…`;
    const fd=new FormData();fd.append("file",f);
    const r=await fetch("/upload",{method:"POST",body:fd});
    if(!r.ok){prog.textContent=`failed: ${f.name} (${r.status})`;return}
  }
  prog.textContent="done";setTimeout(()=>prog.style.display="none",1200);
  loadFiles();
}
fi.addEventListener("change",e=>upload(e.target.files));
["dragenter","dragover"].forEach(ev=>drop.addEventListener(ev,e=>{
  e.preventDefault();drop.classList.add("over")}));
["dragleave","drop"].forEach(ev=>drop.addEventListener(ev,e=>{
  e.preventDefault();drop.classList.remove("over")}));
drop.addEventListener("drop",e=>{if(e.dataTransfer.files.length)upload(e.dataTransfer.files)});
loadFiles();
</script></body></html>"""

LOGIN = """<!doctype html><meta charset=utf-8><title>clip — login</title>
<style>body{background:#0f1115;color:#e6e8ec;font:14px system-ui;margin:0}
.box{max-width:340px;margin:80px auto;padding:24px;background:#161a22;
border:1px solid #2a313d;border-radius:10px}
input,button{width:100%;background:#1d222c;color:#e6e8ec;border:1px solid #2a313d;
border-radius:8px;padding:10px;font:inherit;margin-bottom:10px;box-sizing:border-box}
button{background:#5b9dff;color:#0a1220;border-color:#5b9dff;cursor:pointer}
h1{margin:0 0 14px;font-size:16px}</style>
<div class=box><h1>clip</h1>
<form method=post action="/login">
<input type=password name=token placeholder=token autofocus required>
<button>unlock</button></form></div>"""


@app.get("/")
def home():
    if not authed():
        return LOGIN, 200, {"Content-Type": "text/html; charset=utf-8"}
    import html as h
    text = TEXT_FILE.read_text(errors="replace")
    files_count = sum(1 for _ in FILES_DIR.iterdir())
    meta = f"{len(text)} chars · {files_count} files"
    body = (PAGE.replace("__TEXT__", h.escape(text))
                .replace("__META__", h.escape(meta))
                .replace("__MAX__", str(MAX_MB)))
    return body, 200, {"Content-Type": "text/html; charset=utf-8"}


@app.post("/login")
def login():
    if request.form.get("token") != TOKEN:
        return LOGIN, 403, {"Content-Type": "text/html; charset=utf-8"}
    r = make_response(redirect("/"))
    r.set_cookie("token", TOKEN, max_age=60*60*24*30,
                 httponly=True, samesite="Lax", secure=True)
    return r


@app.post("/save")
def save():
    need_auth()
    TEXT_FILE.write_text(request.form.get("text", ""))
    return "ok\n"


# legacy plain-text endpoints (used by `clip` / `clipw` aliases)
@app.get("/raw")
def raw_get():
    need_auth()
    return TEXT_FILE.read_text(errors="replace"), 200, \
           {"Content-Type": "text/plain; charset=utf-8"}


@app.put("/raw")
def raw_put():
    need_auth()
    TEXT_FILE.write_text(request.get_data(as_text=True))
    return "ok\n"


@app.get("/files")
def files_list():
    need_auth()
    out = []
    for p in sorted(FILES_DIR.iterdir(), key=lambda x: -x.stat().st_mtime):
        if p.is_file():
            out.append({"name": p.name, "size": p.stat().st_size,
                        "mtime": int(p.stat().st_mtime)})
    return jsonify(out)

@app.get("/files.txt")
def files_txt():
    need_auth()
    rows = []
    for p in sorted(FILES_DIR.iterdir(), key=lambda x: -x.stat().st_mtime):
        if p.is_file():
            rows.append(f"{p.stat().st_size:>10}  {p.name}")
    return "\n".join(rows) + "\n", 200, {"Content-Type": "text/plain; charset=utf-8"}

@app.post("/upload")
def upload():
    need_auth()
    f = request.files.get("file")
    if not f or not f.filename:
        abort(400)
    name = secure_filename(f.filename) or "unnamed"
    f.save(FILES_DIR / name)
    return jsonify({"name": name, "size": (FILES_DIR / name).stat().st_size})


@app.get("/file/<path:name>")
def file_get(name):
    need_auth()
    safe = secure_filename(name)
    p = FILES_DIR / safe
    if not safe or not p.is_file():
        abort(404)

    if request.args.get("inline") != "1":
        return send_from_directory(FILES_DIR, safe, as_attachment=True)

    mime, _ = mimetypes.guess_type(safe)
    if mime not in SAFE_INLINE_MIME:
        mime = "text/plain; charset=utf-8"

    resp = send_from_directory(FILES_DIR, safe, as_attachment=False, mimetype=mime)
    resp.headers["Content-Disposition"] = f'inline; filename="{safe}"'
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Content-Security-Policy"] = (
        "default-src 'none'; img-src 'self' data:; "
        "media-src 'self'; style-src 'unsafe-inline'"
    )
    return resp




@app.delete("/file/<path:name>")
def file_del(name):
    need_auth()
    safe = secure_filename(name)
    p = FILES_DIR / safe
    if p.is_file():
        p.unlink()
    return "ok\n"


@app.errorhandler(413)
def too_big(e):
    return f"file too big (max {MAX_MB} MB)\n", 413
