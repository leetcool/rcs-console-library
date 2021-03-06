
package it.ht.rcs.console.task.controller
{
  import flash.events.TimerEvent;
  import flash.filesystem.File;
  import flash.utils.Timer;
  
  import it.ht.rcs.console.DB;
  import it.ht.rcs.console.notifications.NotificationPopup;
  import it.ht.rcs.console.task.model.Task;
  import it.ht.rcs.console.utils.FileDownloader;
  
  import mx.resources.ResourceManager;
  import mx.rpc.events.FaultEvent;
  import mx.rpc.events.ResultEvent;
  
  public class DownloadTask
  {
   
    private var updateTimer: Timer;
    private var fileDownloader: FileDownloader;
    
    [Bindable]
    private var db:DB;
    
    [Bindable]
    public var task: Task;
    [Bindable]
    public var creation_percentage:Object = {bytesLoaded:0, bytesTotal:0};
    [Bindable]
    public var download_percentage:Object = {bytesLoaded:0, bytesTotal:0};
    
    public function running():Boolean
    {
      return (isInProgress() || isDownloading());
    }
    
    public function get desc():String
    {
      return this.task.description;
    }
    
    public function DownloadTask(task: Object, db: DB)
    {
      trace("Creating DownloadTask " + task._id);
      this.task = new Task(task);
      this.db = db;
      if (task.status != 'finished') {
        if (task.file_name != null) 
          NotificationPopup.showNotification(ResourceManager.getInstance().getString('localized_main', 'TASK_NEW', [task.file_name]), 3);
        else
          NotificationPopup.showNotification(ResourceManager.getInstance().getString('localized_main', 'TASK_NOFILE_NEW'), 3);
      }
    }
    
    public function factory(type:String, fileName:String):DownloadTask
    {
      var task: Task;
      DB.instance.task.create({type: type, file_name: fileName}, function(e:ResultEvent):void {
        task = e.result as Task;
      });
      
      return new DownloadTask(task, db);
    }
    
    public function destroy():void
    {
      trace("Deleting task " + task._id);
      db.task.destroy(task);    
    }
    
    public function start_update():void
    {
      if (isFinished() || isError()) {
        creation_percentage.bytesTotal = task.total;
        creation_percentage.bytesLoaded = task.current;
        download_percentage.bytesLoaded = task.total;
        download_percentage.bytesTotal = task.current;
        return;
      }
      
      updateTimer = new Timer(1000);
      updateTimer.addEventListener(TimerEvent.TIMER, function ():void {
        db.task.show(task._id, doUpdate, onUpdateFailure);
      });
      updateTimer.start();
    }
    
    public function isError():Boolean
    {
      return task.status == 'error';
    }
    
    public function isFinished():Boolean
    {
      return task.status == 'finished';
    }
    
    public function isInProgress(): Boolean
    {
      return task.status == 'in_progress';
    }
    
    public function isDownloading(): Boolean
    {
      return task.status == 'download_available';
    }
    
    public function onUpdateFailure(event:FaultEvent):void
    {
      trace("Update failure!!! " + event);
    }
    
    private function doUpdate(event:ResultEvent):void
    {
      // update description, progress and resource
      
      task.status = event.result.status;
      task.current = event.result.current;
      task.total = event.result.total;
      task.resource = event.result.resource;
      task.description = event.result.description;
      
      trace ("Updating task " + event.result._id + " (" + task.status + ") [current: " + task.current + " | total: " + task.total + "]");
      
      switch (task.status) {
        case "in_progress":
          // update creation progress bar
          creation_percentage.bytesTotal = task.total;
          creation_percentage.bytesLoaded = task.current;
          
          trace("Task " + task._id +" in progress.");
          break;
        
        case "download_available":
          // update creation progress bar
          creation_percentage.bytesTotal = task.total;
          creation_percentage.bytesLoaded = task.current;
          
          // downloads are stored into /Desktop/RCS Downloads 
          var path:String = File.desktopDirectory.nativePath + '/RCS Downloads';
          new File(path).createDirectory();
          
          // start the downloader
          var remote_uri:String = 'task/download/' + task.resource._id;
          var local_path:String = path + '/' + task.file_name;
          fileDownloader = new FileDownloader(remote_uri, local_path);
          fileDownloader.onProgress = onDownloadUpdate;
          fileDownloader.onComplete = onDownloadComplete;
          // task.description = "Downloading";
          fileDownloader.download();
          
          trace("Task " + task._id +" is available for download.");
          break;
        
        case "downloading":
          
          trace("Task " + task._id +" is downloading.");
          break;
        
        case "finished":
          // update creation progress bar
          creation_percentage.bytesTotal = task.total;
          //creation_percentage.bytesLoaded = task.current;
          creation_percentage.bytesLoaded = task.total; //??
          // stop the update timer
          updateTimer.stop();
          
          // task.description = "Completed";
          if (task.file_name != null)
            NotificationPopup.showNotification(ResourceManager.getInstance().getString('localized_main', 'TASK_COMPLETE', [task.file_name]),6,true);
          else
            NotificationPopup.showNotification(ResourceManager.getInstance().getString('localized_main', 'TASK_NOFILE_COMPLETE'), 3);
          trace("Task " + task._id +" completed.");
          break;
          
        case "error":
          // update creation progress bar
          creation_percentage.bytesTotal = task.total;
          creation_percentage.bytesLoaded = task.current;
          
          // stop the update timer
          updateTimer.stop();
          if (task.file_name != null)
            NotificationPopup.showNotification(ResourceManager.getInstance().getString('localized_main', 'TASK_ERROR', [task.file_name]));
          else
            NotificationPopup.showNotification(ResourceManager.getInstance().getString('localized_main', 'TASK_NOFILE_ERROR'));
          trace("Task " + task._id +" error.");
          break;
      }
      
      DownloadManager.instance.checkRunning();
    
    }
    
    public function onDownloadUpdate(cur:Number, total:Number):void
    {
      // update download progress bar
      download_percentage.bytesLoaded = cur;
      download_percentage.bytesTotal = total;
    }
    
    public function onDownloadComplete():void
    {
      trace("Task " + task._id + " download finished.");
      DownloadManager.instance.checkRunning();
    }
    
    public function cleanup():void
    {
      if (updateTimer) {
        updateTimer.stop();
        updateTimer = null;
      }
      
      if (fileDownloader) {
        fileDownloader.cancelDownload();
        fileDownloader = null;
      }
      
    }
  }
}