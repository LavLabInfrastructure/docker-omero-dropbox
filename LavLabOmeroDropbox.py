#!/usr/bin/python3
# known limitations: 
#   cannot create subwatches with different parameters consistently
#       fix: properties are keyed by being a parent directory, need a different key system for consistent property matching of subdirectories
#       comment: really just shouldn't structure directories like this
#   likely unnecessarily incompatible with windows and maybe mac.
#       fix: check subprocess and file operations on windows os and mac
#       comment: started writing this with inotify, making platform independence being too expensive to write.
#           In the final version I have switched to Watchdog, an already platform independent watch module. 
#           It would not be difficult for this to be run on the big 3 operating systems and may already, 
#           but I did not code for that and I will just be using linux containers anyway.
# SHOULD KNOW:
#   glencoesoftwares scripts print mostly to stderr
import os
import re
import sys
import time
import yaml
import logging
import tempfile
import subprocess

from types import SimpleNamespace
from shutil import which, copytree
from threading import Thread
from concurrent.futures import ThreadPoolExecutor

from flask import Flask
from waitress import serve

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

logging.basicConfig(level=logging.INFO)

class OmeroDropbox(FileSystemEventHandler):
    DEFAULTS={
        "enable_grafana":True,
        "enable_prometheus":True,
        "max_jobs": 2
    }
    LOCAL_DEFAULTS={
        "orphaned_name":"orphaned",
        "file_format":"zarr",
        "bf2raw_args":[],
        "raw2tiff_args":["--rgb"]
    }
    ARGS=[
        f"--memo-directory=/tmp",
        "-p"
    ]
    running = True
    def __init__(self, yaml) -> None:
        """Loads configuration from yaml file."""
        logging.info("STARTING LAVIOLETTELAB OMERO DROPBOX")
        
        self._statuses=[]
        self._metrics={
            "queued":0,
            "processing":0,
            "processed":0,
            "failed":0
        }

        # containerized versions will require moving config files to docker volume
        if os.path.isfile("/configs/grafana") and os.path.isfile("/etc/grafana/provisioning "):
            copytree("/configs/grafana", "/etc/grafana/provisioning")
            
        global_conf = yaml.pop("global")

        # find glencoe softwares
        self.BF2RAW = global_conf.get("bf2raw")
        self.RAW2TIFF = global_conf.get("raw2tiff")

        if self.BF2RAW is None or self.RAW2TIFF is None:
            self.findGlencoeTools()

        # allow setting new default local settings in global
        for key in self.LOCAL_DEFAULTS: 
            try:
                if type(global_conf[key]) is not type(self.LOCAL_DEFAULTS[key]):
                    logging.error(f"Error in setting new defaults! Parameter: {key} had type: {type(global_conf[key])} expected type: {type(self.DEFAULTS[key])}. Closing...")
                    self.close()
                logging.info(f"Overriding default for parameter: {key}")
                self.LOCAL_DEFAULTS[key] = global_conf[key]
            except KeyError:
                pass

        # load global settings, check types and fill in missing vals
        for key in self.DEFAULTS:
            try:
                if type(global_conf[key]) is not type(self.DEFAULTS[key]):
                    logging.error(f"Error in configuration of global settings! Parameter: {key} had type: {type(global_conf[key])} expected type: {type(self.DEFAULTS[key])}. Closing...")
                    self.close()
            except KeyError:
                logging.warn(f"{key} property was not set, using default value of {self.DEFAULTS[key]}")
                global_conf[key] = self.DEFAULTS[key]
            

        # load dropbox configurations
        self.properties={}
        self._observers = []
        for name in yaml:

            config = yaml[name]
            properties = {"name":name}

            try: # input path is mandatory
                path = os.path.abspath(config["input_path"])
                o = Observer()
                o.schedule(self, path, recursive=True)
                o.daemon = True
                self._observers.append(o)
                properties.update({"input_path":path}) # used for performing proper operations on different dropboxes
                logging.info(f"adding path to watch: {path}")

            except KeyError:
                logging.error(f"Error configuring dropbox '{name}': Missing mandatory 'input_path' property")
                continue
            except Exception as e:
                logging.error(f"Error configuring dropbox '{name}': {e}")
                continue
            try: # output path is mandatory
                path = os.path.abspath(config["output_path"])
                properties.update({"output_path":path}) # used for performing proper operations on different dropboxes

            except KeyError:
                logging.error(f"Error configuring dropbox '{name}': Missing mandatory 'output_path' property")
                continue
            except Exception as e:
                logging.error(f"Error configuring dropbox '{name}': {e}")
                continue

            # fill in missing local settings
            for key in self.LOCAL_DEFAULTS:
                try:
                    val = config[key]
                except:
                    val = self.LOCAL_DEFAULTS[key]
                properties.update({key:val})
            self.properties.update({os.path.abspath(config["input_path"]):properties})


        if len(self.properties) == 0:
            logging.error(f"Failed to configure LaVioletteLab OmeroDropbox. Closing...")
            self.close()
            return

        self.executor = ThreadPoolExecutor(max_workers=global_conf["max_jobs"])
        
        if global_conf["enable_grafana"] is not False: 
            self._enable_grafana=True
        
        if global_conf["enable_prometheus"] is not False:
            self._enable_prometheus=True


    def scrape_stderr(self,proc,status):
        if proc.stderr:
            rv = []
            for line in iter(proc.stderr.readline, b''):
                line = bytes(line).decode().strip()
                try:
                    status["plane"] = re.search('\[\d\/\d\]',line).group(0)
                    status["percent_done"] = re.search('\d+%',line).group(0)
                    status["time_elapsed"], status["time_remaining"] = re.search(
                        '\([^A-Za-z\n]+\)',line).group(0).strip('()').split(' / ')
                except:
                    pass
                rv.append(line)
            return '\n'.join(rv)
                
            
    def _init_grafana(self):
        app = Flask(str(self.__class__.__name__)+"-Grafana")
        @app.route("/")
        def status():
            return self.getStatus()
        serve(app,port=13000)

    def _init_prometheus(self):
        app = Flask(str(self.__class__.__name__)+"-Prometheus")
        @app.route("/")
        def status():
            return self.getMetrics()
        serve(app,port=19090)

    def getStatus(self):
        return self._statuses
    def getMetrics(self):
        return self._metrics
    

    def findGlencoeTools(self):
        if self.BF2RAW is None:
            logging.info("Finding GlencoeSoftware's bioformats2raw")
            self.BF2RAW = os.environ.get("BF2RAW_PATH")
        if self.BF2RAW is None:
            self.BF2RAW = which('bioformats2raw')
        if self.BF2RAW is None:
            logging.error("Could not find GlencoeSoftware Bioformats2Raw! Closing...")
            self.close()
            return
        logging.debug(f"Glencoe Software's bioformats2raw found at {self.BF2RAW}")
        if self.RAW2TIFF is None:
            logging.info("Finding GlencoeSoftware's bioformats2raw")
            self.RAW2TIFF = os.environ.get("RAW2TIFF_PATH")
        if self.RAW2TIFF is None:
            self.RAW2TIFF = which('bioformats2raw')
        if self.RAW2TIFF is None:
            if os.environ.get("NO_GS_TIFF") is True:
                logging.error("Could not find GlencoeSoftware Raw2OmeTiff! Not closing because envar NO_GS_TIFF is enabled!")
            else:
                logging.error("Could not find GlencoeSoftware Raw2OmeTiff! Run 'export NO_GS_TIFF=true' before launch to ignore this.\nClosing...")
                self.close()
                return
        else:
            logging.debug(f"Glencoe Software's raw2ometiff found at {self.RAW2TIFF}")
        
                    
    def on_closed(self, event):
        if not event.is_directory:
            file_path = event.src_path
            # look for matching parent directory 
            for k in self.properties.keys():
                d = str(os.path.dirname(file_path))
                if d == d.removeprefix(k):
                    continue
                break
            self._metrics["queued"] += 1
            self.executor.submit(self.convert, file_path, k)


    def _run_subproc(self, subproc, status) :
        """Starts subproc and watches progress"""
        process = subprocess.Popen(subproc, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # don't block while reading output
        os.set_blocking(process.stdout.fileno(), False)
        os.set_blocking(process.stderr.fileno(), False)
        # while running poll, if done break, else scrape progress
        while process.poll() is None:
            if self.running is False: 
                process.terminate()
                return (1, "QUITTING SUBPROCESS")
            time.sleep(1)
            stderr = self.scrape_stderr(process, status)
        rv = process.returncode

        if rv != 0: 
            rv = (rv, f"There was an error running command:\n{subproc}\nSTDERR:\n{stderr}")
        # hardcode search formissing parameter message, glencoesoftwares exits 0 with help message
        if re.match("Missing", stderr): rv = (1,f"There was an error running command: {subproc}")

        return rv
    

    def convert(self, input_path, k):
        with tempfile.TemporaryDirectory() as tempdir:
            logging.info(f"CONVERTING {input_path}!")
            self._metrics["queued"] -= 1
            self._metrics["processing"] += 1

            # get properties
            props = self.properties[k]

            # get dataset
            rel_path = os.path.dirname(input_path).removeprefix(props["input_path"])
            try:
                dataset = rel_path.split('/')[1]
            except:
                dataset = props["orphaned_name"]

            # get filename
            filename = os.path.basename(input_path)
            logger = logging.getLogger(filename)
            output_path =  os.path.join(props["output_path"],dataset)
            if not os.path.exists(output_path): os.makedirs(output_path)
            commands = []
            if props["file_format"].lower() == "zarr":
                # zarr command only
                output = os.path.join(output_path, os.path.splitext(filename)[0])
                args = [self.BF2RAW, "'"+input_path+"'", "'"+output+"'"]
                args.extend(self.ARGS)
                args.extend(props["bf2raw_args"])
                commands.append(args)
            else:
                # zarr command
                zarrOut = os.path.abspath(tempdir + "/raw")
                args = [self.BF2RAW, "'"+input_path+"'", "'"+zarrOut+"'"]
                args.extend(self.ARGS)
                args.extend(props["bf2raw_args"])
                commands.append(args)
                # tiff command
                output = os.path.join(output_path, os.path.splitext(filename)[0] + ".ome.tiff")
                args = [self.RAW2TIFF, zarrOut, "'"+output+"'"]
                args.extend(["-p"])
                args.extend(props["raw2tiff_args"])
                commands.append(args)
            
            status = {
                "name": filename,
                "plane": "?",
                "percent_done": "?",
                "time_elapsed": "?",
                "time_remaining": "?"
            }
            self._statuses.append(status)

            for command in commands:
                logger.info(f"running command: {command}")
                result = self._run_subproc(' '.join(command), status)
                if result != 0:
                    self._metrics["failed"] += 1
                    logger.warn(f"Error processing {filename} with {command[0]}: {result[1]}")
                    break
        if result == 0:
            logger.info(f"Successfully processed {output}! Cleaning up!")
            os.remove(input_path)
            self._metrics["processed"] += 1
        self._statuses.remove(status)
        self._metrics["processing"] -= 1

    def close(self):
        self.running = False
        try:
            self.executor.shutdown()
        except AttributeError:
            pass
        exit(0)

    def run(self):
        # monitor status with grafana
        if self._enable_grafana: 
            Thread(target=self._init_grafana, daemon=True,
                name=str(self.__class__.__name__)+"-Grafana").start()
        # monitor metrics with prometheus
        if self._enable_prometheus: 
            Thread(target=self._init_prometheus, daemon=True,
                name=str(self.__class__.__name__)+"-Prometheus").start() 
        # queue old files
        for path in self.properties.keys(): # for each dropbox
            for root,d_names,f_names in os.walk(path): # for each file recursively found
                for f in f_names:
                    # emulate close_write event
                    evt = SimpleNamespace()
                    setattr(evt, "is_directory", False)
                    setattr(evt, "src_path", os.path.join(root, f))
                    self.on_closed(evt)
        # start watches
        for o in self._observers: o.start()
        # run
        while self.running:
            time.sleep(1)
        

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: python3 {sys.argv[0]} <yaml_path>")
        sys.exit(1)

    yaml_path = sys.argv[1]

    if not os.path.isfile(yaml_path):
        logging.error("Config not found! Closing...")
        sys.exit(1)
             
    config = yaml.load(open(yaml_path), yaml.CLoader)
    

    # Initialize the ProcessPoolExecutor
    dropbox = OmeroDropbox(config)
    try:
        dropbox.run()
            
    except KeyboardInterrupt:
        dropbox.close()
