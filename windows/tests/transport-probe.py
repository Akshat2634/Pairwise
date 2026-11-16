"""Isolated Windows Go HTTP request-body/connection-close reproduction."""
import collections
import pathlib
import socket
import subprocess
import tempfile
import time
import urllib.request

with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    source = root / 'server.go'
    source.write_text('''package main
import ("net/http"; "io"; "log")
func main() {
 http.HandleFunc("/ignored", func(w http.ResponseWriter,r *http.Request) { w.Write([]byte(`{"ok":true}`)) })
 http.HandleFunc("/drained", func(w http.ResponseWriter,r *http.Request) { io.Copy(io.Discard, r.Body); w.Write([]byte(`{"ok":true}`)) })
 log.Fatal(http.ListenAndServe("127.0.0.1:18089",nil))
}
''')
    binary = root / 'probe.exe'
    subprocess.run(['go','build','-o',str(binary),str(source)],check=True)
    with subprocess.Popen([str(binary)]) as process:
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',18089),0.1): break
                except OSError: time.sleep(.1)
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            for route, body in [('ignored',b'{}'),('drained',b'{}'),('ignored',b'')]:
                results = collections.Counter()
                for _ in range(500):
                    request = urllib.request.Request('http://127.0.0.1:18089/'+route,data=body,headers={'Content-Type':'application/json'})
                    try:
                        with opener.open(request,timeout=5) as response:
                            assert response.read() == b'{"ok":true}'
                        results['success'] += 1
                    except Exception as error:
                        results[type(error).__name__] += 1
                print(route, 'body=', repr(body), dict(results), flush=True)
        finally:
            process.terminate()
            process.wait(timeout=10)
