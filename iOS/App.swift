import UIKit
import MetalKit
import UniformTypeIdentifiers
@main final class AppDelegate:UIResponder,UIApplicationDelegate {
 var window:UIWindow?
 func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?)->Bool{
  let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=UINavigationController(rootViewController:OwnSceneController());window.makeKeyAndVisible();self.window=window;return true
 }
}
@MainActor final class OwnSceneController:UIViewController,UIDocumentPickerDelegate {
 private let scene=NativeSceneLoader(),status=UILabel()
 private var renderer:MetalWorldRenderer?
 private var root:URL?,scoped=false,names:[String]=[],loading=false,hasMesh=false
 private var activeObserver:NSObjectProtocol?
 private var bookmarkTried=false
 private var documents:URL{FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]}
 private let archive="data/x64/levels/gta5/generic/procobj.rpf"
 override func viewDidLoad(){
  super.viewDidLoad();title="Mugoat Own Engine · Lab";view.backgroundColor = .black
  navigationItem.rightBarButtonItem=UIBarButtonItem(title:"Data",style:.plain,target:self,action:#selector(choose))
  navigationItem.leftBarButtonItem=UIBarButtonItem(title:"Mô hình",style:.plain,target:self,action:#selector(models))
  guard let device=MTLCreateSystemDefaultDevice() else{status.text="Thiết bị không có Metal";return}
  let canvas=MTKView(frame:.zero,device:device);canvas.translatesAutoresizingMaskIntoConstraints=false;canvas.colorPixelFormat = .bgra8Unorm_srgb;view.addSubview(canvas)
  status.numberOfLines=3;status.text="Engine riêng đang phát triển. Chọn thư mục game chứa data và b. Chưa có gameplay GTA V.";status.textColor = .white;status.backgroundColor=UIColor.black.withAlphaComponent(0.7);status.font = .monospacedSystemFont(ofSize:11,weight:.regular);status.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(status)
  NSLayoutConstraint.activate([canvas.leadingAnchor.constraint(equalTo:view.leadingAnchor),canvas.trailingAnchor.constraint(equalTo:view.trailingAnchor),canvas.topAnchor.constraint(equalTo:view.topAnchor),canvas.bottomAnchor.constraint(equalTo:view.bottomAnchor),status.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:12),status.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-12),status.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-8)])
  do{renderer=try MetalWorldRenderer(view:canvas);renderer?.metrics={[weak self] text in guard let self,!self.loading,self.hasMesh else{return};self.status.text=text+"\nVuốt: xoay · Chụm: zoom · Chưa có gameplay/texture/animation"}}catch{status.text=error.localizedDescription}
  canvas.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(look(_:))));canvas.addGestureRecognizer(UIPinchGestureRecognizer(target:self,action:#selector(zoom(_:))))
  GameRootLocator.prepareDocuments(documents)
  activeObserver=NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.discover()}}
 }
 override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);discover()}
 deinit{if let activeObserver{NotificationCenter.default.removeObserver(activeObserver)};if scoped{root?.stopAccessingSecurityScopedResource()}}
 private func discover(){
  guard !loading,names.isEmpty else{return}
  if !bookmarkTried {
   bookmarkTried=true
   if let bookmark=UserDefaults.standard.data(forKey:"OwnEngine.rootBookmark"){
    var stale=false
    if let url=try? URL(resolvingBookmarkData:bookmark,options:[],relativeTo:nil,bookmarkDataIsStale:&stale),!stale{open(url,automatic:true);return}
   }
  }
  scanDocuments()
 }
 @objc private func scanDocuments(){guard !loading else{return};open(documents,automatic:true)}
 @objc private func choose(){
  guard !loading else{return}
  let menu=UIAlertController(title:"Dữ liệu game",message:"Có thể chép nguyên thư mục game vào Trên iPhone → Mugoat Own Engine Lab. App sẽ đọc trực tiếp, không sao chép thêm.",preferredStyle:.alert)
  menu.addAction(UIAlertAction(title:"Tìm trong Documents",style:.default){[weak self] _ in self?.scanDocuments()})
  menu.addAction(UIAlertAction(title:"Chọn thư mục qua Tệp",style:.default){[weak self,weak menu] _ in menu?.dismiss(animated:true){self?.pickFolder()}})
  menu.addAction(UIAlertAction(title:"Hướng dẫn",style:.default){[weak self,weak menu] _ in menu?.dismiss(animated:true){self?.showInstructions()}})
  menu.addAction(UIAlertAction(title:"Đóng",style:.cancel));present(menu,animated:true)
 }
 private func pickFolder(){
  let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false);picker.delegate=self;picker.allowsMultipleSelection=false;picker.directoryURL=documents;picker.shouldShowFileExtensions=true;present(picker,animated:true)
 }
 private func showInstructions(){
  let alert=UIAlertController(title:"Chép data bằng Tệp",message:GameRootLocator.instructions,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"Đã hiểu",style:.default));present(alert,animated:true)
 }
 func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){if let url=urls.first{open(url,automatic:false)}}
 func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController){if names.isEmpty{status.text="Có thể chép game vào thư mục app bằng Tệp rồi chọn Data → Tìm trong Documents."}}
 private func open(_ url:URL,automatic:Bool){
  guard !loading else{return}
  if scoped{root?.stopAccessingSecurityScopedResource()};root=url;scoped=url.startAccessingSecurityScopedResource();loading=true;hasMesh=false;names=[];renderer?.clearMesh();status.text="Đang tìm thư mục game…"
  Task{do{
   let actual=await Task.detached(priority:.utility){GameRootLocator.find(in:url)}.value
   guard let actual else{
    loading=false
    status.text=automatic ? "Chưa thấy data. Chép game vào Trên iPhone → Mugoat Own Engine Lab → game, sau đó mở lại app hoặc nhấn Data → Tìm trong Documents." : "Thư mục chưa có đủ data và b. Hãy chọn thư mục game hoặc thư mục cha chứa game; không chọn riêng data."
    if automatic,url.standardizedFileURL != documents.standardizedFileURL{scanDocuments()}
    return
   }
   status.text="Đã tìm thấy \(actual.lastPathComponent). Đang đọc khóa asset và bảng RPF…"
   try await scene.open(root:actual);names=try await scene.assets(archive:archive)
   if url.standardizedFileURL != documents.standardizedFileURL,let bookmark=try? url.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil){UserDefaults.standard.set(bookmark,forKey:"OwnEngine.rootBookmark")}
   loading=false;status.text="Đã đọc \(names.count) drawable từ \(actual.lastPathComponent). Nhấn Mô hình."
  }catch{
   loading=false;status.text="Không đọc được data: "+error.localizedDescription
   if automatic,url.standardizedFileURL != documents.standardizedFileURL{scanDocuments()}
  }}
 }
 @objc private func models(){
  guard !loading,!names.isEmpty else{return}
  let browser=ModelBrowser(names:names){[weak self] name in self?.load(name)};present(UINavigationController(rootViewController:browser),animated:true)
 }
 private func load(_ name:String){
  loading=true;hasMesh=false;renderer?.clearMesh();status.text="Đang giải mã geometry: "+name
  Task{do{let mesh=try await scene.load(archive:archive,asset:name);try renderer?.setMesh(mesh);hasMesh=true;loading=false;status.text="\(name): \(mesh.vertices.count) vertex, \(mesh.triangleCount) triangle"}catch{loading=false;status.text=error.localizedDescription}}
 }
 @objc private func look(_ gesture:UIPanGestureRecognizer){let delta=gesture.translation(in:view);renderer?.yaw+=Float(delta.x)*0.008;renderer?.pitch+=Float(delta.y)*0.008;gesture.setTranslation(.zero,in:view)}
 @objc private func zoom(_ gesture:UIPinchGestureRecognizer){if let renderer{renderer.zoom=max(0.3,min(20,renderer.zoom/Float(gesture.scale)))};gesture.scale=1}
}
@MainActor final class ModelBrowser:UITableViewController {
 let names:[String];let select:(String)->Void
 init(names:[String],select:@escaping(String)->Void){self.names=names;self.select=select;super.init(style:.plain)}
 required init?(coder:NSCoder){fatalError("init(coder:) unsupported")}
 override func viewDidLoad(){super.viewDidLoad();title="Static drawables";navigationItem.rightBarButtonItem=UIBarButtonItem(barButtonSystemItem:.done,target:self,action:#selector(close));tableView.register(UITableViewCell.self,forCellReuseIdentifier:"asset")}
 @objc private func close(){dismiss(animated:true)}
 override func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{names.count}
 override func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell{let cell=tableView.dequeueReusableCell(withIdentifier:"asset",for:indexPath);cell.textLabel?.text=names[indexPath.row];return cell}
 override func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath){let name=names[indexPath.row];dismiss(animated:true){self.select(name)}}
}
