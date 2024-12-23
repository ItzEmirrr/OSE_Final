#!/bin/bash 
 
# Logging
LOG_FILE="/var/log/deploy_django.log" 
echo "Start of deployment: $(date)" >> $LOG_FILE 
 
# Check of superuser rights
if [ "$EUID" -ne 0 ]; then 
  echo "Please run the script with superuser rights." | tee -a $LOG_FILE 
  exit 1 
fi 
 
# Params 
REPO_URL="https://github.com/DireSky/OSEExam.git" 
APP_DIR="/mnt/c/Users/Lenovo/final/OSEExam"  # Folder for cloning 
APP_NAME="django_app" 
PYTHON_VERSION="python3" 
PROJECT_DIR="$APP_DIR/testPrj"  # Path to the project after cloning
 
# Installing the required packages 
apt update && apt install -y $PYTHON_VERSION $PYTHON_VERSION-venv git curl net-tools || { 
  echo "Error installing packages" | tee -a $LOG_FILE 
  exit 1 
} 
 
# Cloning a repository
if [ ! -d "$APP_DIR" ]; then 
  git clone $REPO_URL $APP_DIR || { 
    echo "Error cloning repository" | tee -a $LOG_FILE 
    exit 1 
  } 
else 
  echo "Directory $APP_DIR already exists. Skipping cloning." | tee -a $LOG_FILE 
fi 
 
# Create subdirectory testPrj (if it does not already exist)
if [ ! -d "$PROJECT_DIR" ]; then 
  echo "Created a directory for the project: $PROJECT_DIR" | tee -a $LOG_FILE 
  mkdir -p "$PROJECT_DIR" || { 
    echo "Error creating directory for project $PROJECT_DIR" | tee -a $LOG_FILE 
    exit 1 
  } 
fi 
 
# Move to the project directory 
cd $PROJECT_DIR || exit 
 
# Creating a virtual environment
if [ ! -d "venv" ]; then 
  $PYTHON_VERSION -m venv venv || { 
    echo "Error creating virtual environment" | tee -a $LOG_FILE 
    exit 1 
  } 
fi 
source venv/bin/activate 
 
# Installing dependencies
if [ -f "$PROJECT_DIR/requirements.txt" ]; then 
  pip install Django 
  pip install gunicorn 
  pip install whitenoise  || { 
    echo "Error installing dependencies" | tee -a $LOG_FILE 
    deactivate 
    exit 1 
  } 
else 
  echo "File requirements.txt not found" | tee -a $LOG_FILE 
fi 
 
deactivate 
 
# Migrations and collection of static files
source venv/bin/activate 
python manage.py migrate || { 
  echo "Error running migrations" | tee -a $LOG_FILE 
  deactivate 
  exit 1 
} 
python manage.py collectstatic --noinput || { 
  echo "Error building static files" | tee -a $LOG_FILE 
  deactivate 
  exit 1 
} 
deactivate 
 
# Adding settings to settings.py
SETTINGS_FILE="$PROJECT_DIR/settings.py" 
 
# Adding WhiteNoise
if ! grep -q "whitenoise.middleware.WhiteNoiseMiddleware" "$SETTINGS_FILE"; then 
  echo "Add WhiteNoise settings to settings.py" | tee -a $LOG_FILE 
  sed -i "/'django.middleware.security.SecurityMiddleware'/a \ \ \ \ 'whitenoise.middleware.WhiteNoiseMiddleware'," "$SETTINGS_FILE" 
  echo -e "\n# WhiteNoise settings" >> "$SETTINGS_FILE" 
  echo "STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'" >> "$SETTINGS_FILE" 
  echo "STATIC_ROOT = os.path.join(BASE_DIR, 'static')" >> "$SETTINGS_FILE" 
fi 
 
# Adding ALLOWED_HOSTS 
if ! grep -q "ALLOWED_HOSTS" "$SETTINGS_FILE"; then 
  echo "Add ALLOWED_HOSTS to settings.py" | tee -a $LOG_FILE 
  echo -e "\n# ALLOWED_HOSTS settings" >> "$SETTINGS_FILE" 
  echo "ALLOWED_HOSTS = ['localhost', '127.0.0.1', '0.0.0.0', '*']" >> "$SETTINGS_FILE" 
fi 
 
# Adding STATIC_ROOT (if not already added) 
if ! grep -q "STATIC_ROOT" "$SETTINGS_FILE"; then 
  echo "Add STATIC_ROOT to settings.py" | tee -a $LOG_FILE 
  echo "STATIC_ROOT = os.path.join(BASE_DIR, 'static')" >> "$SETTINGS_FILE" 
fi 
 
# Function to check and release a port 
free_port() { 
  PORT=$1 
  PID=$(netstat -ltnp | grep ":$PORT " | awk '{print $7}' | cut -d'/' -f1) 
  if [ ! -z "$PID" ]; then 
    echo "Port $PORT is occupied by process with PID $PID. Terminating process..." | tee -a $LOG_FILE 
    kill -9 $PID || { 
      echo "Failed to terminate the process using the port $PORT" | tee -a $LOG_FILE 
      exit 1 
    } 
  fi 
} 
 
# Freeing the port 
PORT=5555 
free_port $PORT 
 
# Automatically launch Gunicorn 
start_gunicorn() { 
  while true; do 
    source venv/bin/activate 
    echo "Launching Gunicorn..." | tee -a

    $LOG_FILE 
    $PROJECT_DIR/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:$PORT testPrj.wsgi:application || { 
      echo "Gunicorn has terminated with an error. Restarting..." | tee -a $LOG_FILE 
    } 
    deactivate 
    sleep 3 # Waiting before restarting if Gunicorn crashes 
  done 
} 
 
# Run Gunicorn in the background 
start_gunicorn & 
 
# Checking app availability 
APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT) 
if [ "$APP_STATUS" -eq 200 ]; then 
  echo "The application has been successfully deployed and is available at http://localhost:$PORT" | tee -a $LOG_FILE 
else 
  echo "Error: Application is not available. Check your settings." | tee -a $LOG_FILE 
fi 
 
exit 0