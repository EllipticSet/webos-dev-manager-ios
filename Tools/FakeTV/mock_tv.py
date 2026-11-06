import os,sys,socket,threading,subprocess,re,stat as st,time
import paramiko
from paramiko import SFTPServerInterface,SFTPServer,SFTPAttributes,SFTPHandle,SFTP_OK,SFTP_NO_SUCH_FILE
T="/tmp/faketv"
paramiko.Transport._preferred_kex=("diffie-hellman-group14-sha1",)
paramiko.Transport._preferred_ciphers=("aes128-ctr",)
paramiko.Transport._preferred_macs=("hmac-sha1",)
paramiko.Transport._preferred_keys=("ssh-rsa",)
paramiko.Transport._preferred_pubkeys=("ssh-rsa","ssh-ed25519")
HOST=paramiko.RSAKey(filename=T+"/host_rsa")
AUTH=paramiko.RSAKey(filename=T+"/tvkey.pem")
MAP=[("/media/developer",T+"/media/developer"),("/var/luna",T+"/var/luna"),("/var/log/messages",T+"/var/log/messages"),("/tmp/var",T+"/tmpvar")]
def rw(s):
    for a,b in MAP: s=s.replace(a,b)
    return s.replace(T+T,T).replace("/private"+T,T)
def log(*a): print(*a,flush=True)
class Srv(paramiko.ServerInterface):
    def __init__(s): s.user=None; s.ev=threading.Event()
    def get_allowed_auths(s,u): return "publickey,password"
    def check_auth_publickey(s,u,k):
        try: extra=open(T+"/home/.ssh/authorized_keys").read()
        except OSError: extra=""
        ok=k.get_base64()==AUTH.get_base64() or (u=="root" and k.get_base64() in extra); log("auth",u,k.get_name(),ok); s.user=u
        return paramiko.AUTH_SUCCESSFUL if ok and u in("prisoner","root") else paramiko.AUTH_FAILED
    def check_auth_password(s,u,p):
        s.user=u; return paramiko.AUTH_SUCCESSFUL if u=="root" and p=="alpine" else paramiko.AUTH_FAILED
    def check_channel_request(s,k,c): return paramiko.OPEN_SUCCEEDED
    def check_channel_pty_request(s,*a): log("pty refused"); return False
    def check_channel_exec_request(s,c,cmd):
        threading.Thread(target=run,args=(c,cmd.decode(),s.user),daemon=True).start(); return True
    def check_channel_shell_request(s,c):
        threading.Thread(target=run,args=(c,None,s.user),daemon=True).start(); return True
def run(c,cmd,user):
    log("exec",user,cmd)
    env=dict(os.environ,PATH=T+"/bin:/usr/bin:/bin:/usr/sbin:/sbin",TV_USER=user,HOME=T+"/media/developer" if user=="prisoner" else T+"/home")
    p=subprocess.Popen(["/bin/sh","-c",rw(cmd)] if cmd else ["/bin/sh"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,cwd=env["HOME"],start_new_session=True)
    def pump(f,send):
        while True:
            d=os.read(f.fileno(),32768)
            if not d: return
            try: send(d)
            except Exception: return
    a=threading.Thread(target=pump,args=(p.stdout,c.sendall));b=threading.Thread(target=pump,args=(p.stderr,c.sendall_stderr));a.start();b.start()
    def inp():
        while True:
            try: d=c.recv(32768)
            except Exception: d=b""
            if not d: break
            try: p.stdin.write(d);p.stdin.flush()
            except Exception: break
        try: os.killpg(p.pid,15)
        except Exception: pass
    if cmd is None: threading.Thread(target=inp,daemon=True).start()
    else:
        def watch():
            while p.poll() is None:
                if c.closed or c.get_transport() is None or not c.get_transport().is_active():
                    os.killpg(p.pid,15); return
                time.sleep(.3)
        threading.Thread(target=watch,daemon=True).start()
    p.wait();a.join(1);b.join(1)
    try: c.send_exit_status(p.returncode if p.returncode>=0 else 143); c.close()
    except Exception: pass
class H(SFTPHandle):
    def stat(s): return SFTPAttributes.from_stat(os.fstat(s.readfile.fileno()))
class Sf(SFTPServerInterface):
    def list_folder(s,path):
        path=rw(path);out=[]
        try:
            for n in os.listdir(path):
                a=SFTPAttributes.from_stat(os.lstat(os.path.join(path,n)));a.filename=n;out.append(a)
        except OSError as e: return SFTPServer.convert_errno(e.errno)
        return out
    def stat(s,p):
        try: return SFTPAttributes.from_stat(os.stat(rw(p)))
        except OSError as e: return SFTPServer.convert_errno(e.errno)
    def lstat(s,p):
        try: return SFTPAttributes.from_stat(os.lstat(rw(p)))
        except OSError as e: return SFTPServer.convert_errno(e.errno)
    def open(s,p,flags,attr):
        p=rw(p)
        try:
            fd=os.open(p,flags,0o644)
            m="r+b" if flags&os.O_RDWR else ("wb" if flags&os.O_WRONLY else "rb")
            f=os.fdopen(fd,m)
        except OSError as e: return SFTPServer.convert_errno(e.errno)
        h=H(flags);h.filename=p;h.readfile=f;h.writefile=f;return h
    def remove(s,p):
        try: os.remove(rw(p));return SFTP_OK
        except OSError as e: return SFTPServer.convert_errno(e.errno)
    def canonicalize(s,p): return os.path.normpath("/"+p.lstrip("/"))
def client(sock):
    t=paramiko.Transport(sock);t.add_server_key(HOST)
    t.set_subsystem_handler("sftp",SFTPServer,Sf)
    t.start_server(server=Srv())
    while t.is_active(): time.sleep(1)
l=socket.socket();l.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);l.bind(("127.0.0.1",9922));l.listen(50);log("up")
while True:
    c,_=l.accept();threading.Thread(target=client,args=(c,),daemon=True).start()
