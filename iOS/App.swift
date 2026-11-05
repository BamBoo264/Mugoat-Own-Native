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
 private var sceneSummary=""
 private var metricWindows=0
 private let flightPad=UIStackView()
 private var held=Set<Int>()
 private var backgroundObserver:NSObjectProtocol?

 private var documents:URL{FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]}
 private let archive="data/x64/levels/gta5/generic/procobj.rpf"
 override func viewDidLoad(){
  super.viewDidLoad();title="Own Native · 0.0.4";view.backgroundColor = .black
  navigationItem.rightBarButtonItem=UIBarButtonItem(title:"Data",style:.plain,target:self,action:#selector(choose))
  navigationItem.leftBarButtonItems=[UIBarButtonItem(title:"Mô hình",style:.plain,target:self,action:#selector(models)),UIBarButtonItem(title:"Bản đồ thử",style:.plain,target:self,action:#selector(maps))]
  guard let device=MTLCreateSystemDefaultDevice() else{status.text="Thiết bị không có Metal";return}
  let canvas=MTKView(frame:.zero,device:device);canvas.translatesAutoresizingMaskIntoConstraints=false;canvas.colorPixelFormat = .bgra8Unorm_srgb;view.addSubview(canvas)
  status.numberOfLines=4;status.text="Engine riêng đang phát triển. Chọn thư mục game chứa data và b. Chưa có gameplay GTA V.";status.textColor = .white;status.backgroundColor=UIColor.black.withAlphaComponent(0.7);status.font = .monospacedSystemFont(ofSize:11,weight:.regular);status.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(status)
  NSLayoutConstraint.activate([canvas.leadingAnchor.constraint(equalTo:view.leadingAnchor),canvas.trailingAnchor.constraint(equalTo:view.trailingAnchor),canvas.topAnchor.constraint(equalTo:view.topAnchor),canvas.bottomAnchor.constraint(equalTo:view.bottomAnchor),status.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:12),status.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-12),status.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-8)])
  do{renderer=try MetalWorldRenderer(view:canvas);renderer?.metrics={[weak self] text in guard let self,!self.loading,self.hasMesh else{return};self.metricWindows+=1;if self.metricWindows%15==0{self.log(text)};self.status.text=text+"\n"+self.sceneSummary+"\nChưa có gameplay/texture/animation"}}catch{status.text=error.localizedDescription}
  canvas.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(look(_:))));canvas.addGestureRecognizer(UIPinchGestureRecognizer(target:self,action:#selector(zoom(_:))))
  let tools=UIStackView();tools.axis = .horizontal;tools.distribution = .fillEqually;tools.spacing=8;tools.translatesAutoresizingMaskIntoConstraints=false
  for (title,selector) in [("Thử tổng hợp",#selector(integration)),("Bay / Xoay",#selector(flight)),("Đặt lại",#selector(resetCamera)),("Culling bật/tắt",#selector(toggleCulling))]{
   let b=UIButton(type:.system);b.configuration = .tinted();b.setTitle(title,for:.normal);b.addTarget(self,action:selector,for:.touchUpInside);tools.addArrangedSubview(b)
  }
  view.addSubview(tools)
  flightPad.axis = .horizontal;flightPad.distribution = .fillEqually;flightPad.spacing=8;flightPad.translatesAutoresizingMaskIntoConstraints=false;flightPad.isHidden=true
  for (i,title) in ["← Trái","Phải →","↑ Tiến","↓ Lùi","Lên","Xuống"].enumerated(){
   let b=UIButton(type:.system);b.configuration = .filled();b.setTitle(title,for:.normal);b.tag=i;b.isMultipleTouchEnabled=true
   b.addTarget(self,action:#selector(moveDown(_:)),for:.touchDown)
   b.addTarget(self,action:#selector(moveUp(_:)),for:[.touchUpInside,.touchUpOutside,.touchCancel,.touchDragExit]);flightPad.addArrangedSubview(b)
  }
  view.addSubview(flightPad)
  NSLayoutConstraint.activate([tools.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:4),tools.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:12),tools.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-12),tools.heightAnchor.constraint(equalToConstant:40),flightPad.leadingAnchor.constraint(equalTo:tools.leadingAnchor),flightPad.trailingAnchor.constraint(equalTo:tools.trailingAnchor),flightPad.bottomAnchor.constraint(equalTo:status.topAnchor,constant:-8),flightPad.heightAnchor.constraint(equalToConstant:44)])
  backgroundObserver=NotificationCenter.default.addObserver(forName:UIApplication.willResignActiveNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.stopMovement()}}
  GameRootLocator.prepareDocuments(documents)
  activeObserver=NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.discover()}}
 }
 override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);discover()}
 deinit{if let backgroundObserver{NotificationCenter.default.removeObserver(backgroundObserver)};if let activeObserver{NotificationCenter.default.removeObserver(activeObserver)};if scoped{root?.stopAccessingSecurityScopedResource()}}
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
  menu.addAction(UIAlertAction(title:"Chia sẻ log engine",style:.default){[weak self,weak menu] _ in menu?.dismiss(animated:true){self?.shareLog()}})
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
 private func log(_ text:String){
  let folder=documents.appendingPathComponent("Logs")
  do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   let file=folder.appendingPathComponent("engine-lab.log"),line="[\(ISO8601DateFormatter().string(from:Date()))] \(text)\n"
   if !FileManager.default.fileExists(atPath:file.path){try Data().write(to:file)}
   let handle=try FileHandle(forWritingTo:file);defer{try? handle.close()};try handle.seekToEnd();try handle.write(contentsOf:Data(line.utf8))
  }catch{print("Engine diagnostic write failed")}
 }
 private func shareLog(){
  log("Export diagnostics 0.0.4")
  let sheet=UIActivityViewController(activityItems:[documents.appendingPathComponent("Logs/engine-lab.log")],applicationActivities:nil)
  sheet.popoverPresentationController?.sourceView=view;sheet.popoverPresentationController?.sourceRect=CGRect(x:view.bounds.midX,y:view.bounds.midY,width:1,height:1);present(sheet,animated:true)
 }
 override func didReceiveMemoryWarning(){super.didReceiveMemoryWarning();log("Memory warning: release archive index; keep active scene");Task{await scene.releaseCaches()}}
 private func stopMovement(){held=[];renderer?.movement = .zero}
 private func syncPad(){stopMovement();flightPad.isHidden = !(renderer?.flying ?? false)}
 @objc private func flight(){guard !loading,hasMesh else{return};renderer?.toggleFlight();syncPad()}
 @objc private func resetCamera(){renderer?.resetCamera();syncPad()}
 @objc private func toggleCulling(){renderer?.culling.toggle();log("Culling: \(renderer?.culling ?? false)")}
 @objc private func moveDown(_ button:UIButton){held.insert(button.tag);updateMovement()}
 @objc private func moveUp(_ button:UIButton){held.remove(button.tag);updateMovement()}
 private func updateMovement(){
  func axis(_ plus:Int,_ minus:Int)->Float{(held.contains(plus) ? 1:0)-(held.contains(minus) ? 1:0)}
  renderer?.movement=Vec3(x:axis(1,0),y:axis(2,3),z:axis(4,5))
 }
 @objc private func integration(){
  guard !loading,!names.isEmpty else{return}
  loading=true;hasMesh=false;stopMovement();renderer?.clearMesh();flightPad.isHidden=true;status.text="Đang tải bài thử tổng hợp: YTYP + 3 sector + camera + culling…";log("Combined integration start")
  Task{do{
   let result=try await scene.integrationScene();try renderer?.setScene(result);hasMesh=true;loading=false;syncPad()
   sceneSummary="\(result.chunks.count) sector · camera Bay / Xoay · vuốt nhìn, chụm chỉnh tốc độ/zoom"
   status.text=result.report;log(result.report+"\nMesh bytes: \(result.bytes)")
  }catch{loading=false;status.text=error.localizedDescription;log("Integration failed: "+error.localizedDescription)}}
 }
 @objc private func maps(){
  guard !loading,!names.isEmpty else{return}
  loading=true;status.text="Đang đọc danh sách YMAP Downtown…"
  Task{do{let list=try await scene.mapNames();loading=false
   let browser=ModelBrowser(names:list){[weak self] name in self?.loadSector(name)}
   present(UINavigationController(rootViewController:browser),animated:true)
  }catch{loading=false;status.text=error.localizedDescription}}
 }
 private func loadSector(_ name:String){
  loading=true;hasMesh=false;renderer?.clearMesh();status.text="Đang giải mã sector "+name
  Task{do{let result=try await scene.sector(name);try renderer?.setMesh(result.mesh);loading=false;hasMesh=true;sceneSummary=result.report;syncPad();log(name+": "+result.report)
   status.text=name+"\n"+result.report+"\nVuốt xoay · Chụm zoom · Chưa có texture/gameplay"
  }catch{loading=false;status.text=error.localizedDescription}}
 }
 @objc private func models(){
  guard !loading,!names.isEmpty else{return}
  let browser=ModelBrowser(names:names){[weak self] name in self?.load(name)};present(UINavigationController(rootViewController:browser),animated:true)
 }
 private func load(_ name:String){
  loading=true;hasMesh=false;renderer?.clearMesh();status.text="Đang giải mã geometry: "+name
  Task{do{let mesh=try await scene.load(archive:archive,asset:name);try renderer?.setMesh(mesh);hasMesh=true;loading=false;sceneSummary=name;syncPad();status.text="\(name): \(mesh.vertices.count) vertex, \(mesh.triangleCount) triangle"}catch{loading=false;status.text=error.localizedDescription}}
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
