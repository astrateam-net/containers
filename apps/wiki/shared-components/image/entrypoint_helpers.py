import os
import pwd
import shutil
import logging
import uuid
import re
import jinja2 as j2

logging.basicConfig(level=logging.DEBUG)

def str2bool(s):
    """
    Converts a string to its boolean value based on common representations of truthfulness.
    The function interprets several string values as `True`: 'yes', 'true', 't', 'y', '1'.
    Any other string value is interpreted as `False`. The comparison is case-insensitive.
    Parameters:
    - s (str): The string to convert to a boolean. This can be any string value.
    Returns:
    - bool: The boolean value of the input string. Returns `True` if the string represents a truthy value
            ('yes', 'true', 't', 'y', '1'), and `False` otherwise.
    """
    if str(s).lower() in ('yes', 'true', 't', 'y', '1'):
        return True
    return False

def str2bool_or(s, default):
    """
    Convert a string to a boolean value, with a fallback to a default value if the string is None.
    Parameters:
    - s (str): The string to convert.
    - default (bool): The default boolean value to return if `s` is None.
    Returns:
    - bool: The converted boolean value, or `default` if `s` is None.
    """
    # If the string is set, interpret it as a bool, or fallback to a
    # default.
    if s is None:
        return default
    return str2bool(s)

def is_verbose_logging():
    """
    Determine whether verbose logging is enabled based on the environment variable "VERBOSE_LOGS".
    Returns:
    - bool: True if verbose logging is enabled (i.e., if the "VERBOSE_LOGS" environment variable is set to 'true'),
            False otherwise.
    """
    return str2bool_or(os.environ.get("VERBOSE_LOGS"), False)

def escape_ips(ips):
    """
    Escape all IP addresses in a given string by adding backslashes before each dot, while avoiding double-escaping.
    Parameters:
    - ips (str): A string containing IP addresses separated by '|'. Each IP address may or may not be already escaped.
    Returns:
    - str: A modified string where all IP addresses have been escaped appropriately. If the IP addresses were
           already escaped in the input, they are not double-escaped.
    """
    if is_verbose_logging():
        logging.debug("Starting to escape IP addresses: %s", ips)
    escaped_ips = []
    for ip in ips.split('|'):
        # If the IP is not already escaped, escape it
        if not re.search(r'\\', ip):
            ip = ip.replace('.', '\\.')
            if is_verbose_logging():
                logging.debug("Escaped IP address: %s", ip)
        escaped_ips.append(ip)
    escaped_ips_str = '|'.join(escaped_ips)
    if is_verbose_logging():
        logging.debug("Final escaped IP addresses string: %s", escaped_ips_str)
    return escaped_ips_str

######################################################################
# Setup inputs and outputs

# Import all ATL_* and Dockerfile environment variables. We lower-case
# these for compatibility with Ansible template convention. We also
# support CATALINA variables from older versions of the Docker images
# for backwards compatibility, if the new version is not set.
# For the ATL_TOMCAT_TRUSTEDPROXIES and ATL_TOMCAT_INTERNALPROXIES
# environment variables, any IP addresses are escaped to ensure they
# are correctly formatted
env = {k.lower(): escape_ips(v.strip('"')) if k.lower() in ['atl_tomcat_trustedproxies', 'atl_tomcat_internalproxies'] else v
       for k, v in os.environ.items()}


# Setup Jinja2 for templating
jenv = j2.Environment(
    loader=j2.FileSystemLoader('/opt/atlassian/etc/'),
    autoescape=j2.select_autoescape(['xml']))


######################################################################
# Utils

def set_perms(path, user, group, mode):
    """
    Set ownership and permissions for a given file or directory path.
    Parameters:
    - path (str): The file or directory path for which the ownership and permissions will be set.
    - user (str): The name of the user who will be set as the owner of the path.
    - group (str): The name of the group that will be set for the path.
    - mode (int): The permissions to set for the path, in octal format (e.g., 0o644).
    """
    if is_verbose_logging():
        logging.debug("Setting permissions for %s with user:%s, group:%s, mode:%s", path, user, group, oct(mode))
    try:
        shutil.chown(path, user=user, group=group)
    except PermissionError:
        logging.warning("Could not chown path %s to %s:%s due to insufficient permissions", path, user, group)

    try:
        os.chmod(path, mode)
    except PermissionError:
        logging.warning("Could not chmod path %s to %s due to insufficient permissions", path, mode)

def set_tree_perms(path, user, group, mode):
    """
    Recursively set ownership and permissions for a directory and all its subdirectories and files.
    Parameters:
    - path (str): The root directory path for which the ownership and permissions will be set recursively.
    - user (str): The name of the user who will be set as the owner of the directory and its contents.
    - group (str): The name of the group that will be set for the directory and its contents.
    - mode (int): The permissions to set for the directory and its contents, in octal format (e.g., 0o644).
    """
    if is_verbose_logging():
        logging.debug("Setting permissions for tree starting at %s with user:%s, group:%s, mode:%s", path, user, group, oct(mode))
    set_perms(path, user, group, mode)
    for dirpath, _, filenames in os.walk(path):
        if is_verbose_logging():
            logging.debug("Setting permissions for directory %s", dirpath)
        set_perms(dirpath, user, group, mode)
        for filename in filenames:
            file_path = os.path.join(dirpath, filename)
            if is_verbose_logging():
                logging.debug("Setting permissions for file %s", file_path)
            set_perms(file_path, user, group, mode)

def check_perms(path, uid, gid, mode):
    """
    Check if a file or directory at a given path has the specified ownership and permissions.
    Parameters:
    - path (str): The file or directory path to check.
    - uid (int): The user ID that the path should belong to.
    - gid (int): The group ID that the path should belong to.
    - mode (int): The permissions that the path should have, in octal format (e.g., 0o644).
    Returns:
    - bool: True if the path has the specified ownership and permissions, False otherwise.
    """
    if is_verbose_logging():
        logging.debug("Checking permissions for %s", path)
    stat = os.stat(path)
    result = all([
        stat.st_uid == int(uid),
        stat.st_gid == int(gid),
        stat.st_mode & mode == mode
    ])
    if is_verbose_logging():
        logging.debug("Permissions check for %s: %s", path, result)
    return result

def gen_cfg(tmpl, target, user='root', group='root', mode=0o644, overwrite=True):
    """
    Generate a configuration file from a Jinja2 template.
    Parameters:
    - tmpl (str): The name of the template file to use.
    - target (str): The path where the generated configuration file will be written.
    - user (str, optional): The name of the user who will own the generated file. Defaults to 'root'.
    - group (str, optional): The name of the group for the generated file. Defaults to 'root'.
    - mode (int, optional): The permissions to set for the generated file, in octal format. Defaults to 0o644.
    - overwrite (bool, optional): Whether to overwrite the target file if it already exists. Defaults to True.
    """
    if is_verbose_logging():
        logging.debug("Starting to generate config for %s from template %s", target, tmpl)
    if not overwrite and os.path.exists(target):
        logging.info("%s exists; skipping.", target)
        return

    logging.info("Generating %s from template %s", target, tmpl)
    cfg = jenv.get_template(tmpl).render(env)
    try:
        with open(target, 'w', encoding='utf-8') as fd:
            fd.write(cfg)
    except (OSError, PermissionError) as e:
        logging.warning("Permission problem writing '%s': %s; skipping", target, e)
    else:
        set_tree_perms(target, user, group, mode)
        if is_verbose_logging():
            logging.debug("Finished setting permissions for %s", target)

def gen_container_id():
    """
    Generate a unique container ID and optionally update the environment variable 'local_container_id' with a value
    from a file at '/etc/container_id', if it exists and is not empty.
    """
    if is_verbose_logging():
        logging.debug("Generating container ID.")
    env['uuid'] = uuid.uuid4().hex
    try:
        with open('/etc/container_id', encoding='utf-8') as fd:
            lcid = fd.read().strip()
            if lcid:
                env['local_container_id'] = lcid
                if is_verbose_logging():
                    logging.debug("Local container ID set: %s", lcid)
    except FileNotFoundError:
        if is_verbose_logging():
            logging.debug("/etc/container_id not found, skipping.")

def unset_secure_vars():
    """
    Unset environment variables that are potentially secure/sensitive.
    """
    if is_verbose_logging():
        logging.debug("Starting to unset secure environment variables")

    for key in list(os.environ.keys()):
        if is_secured_var(key):
            logging.warning("Unsetting environment var %s", key)
            del os.environ[key]

def is_secured_var(key):
    """
    Check if the environment variable is considered sensitive, taking into account an allowlist and specific patterns.
    Parameters:
    - key (str): The environment variable key to check.
    Returns:
    - bool: True if the key contains any of the secure keywords and is not in the allowlist or matches an exception pattern.
    """
    secure_keywords = ('PASS', 'SECRET', 'TOKEN')

    # Check if key contains any secure keywords
    if not any(kw in key.upper() for kw in secure_keywords):
        return False

    # users can pass a comma separated list of env vars to allowlist and skip unsetting
    vars_in_allowlist = os.environ.get("ATL_ALLOWLIST_SENSITIVE_ENV_VARS", "").split(",")

    # add known non-sensitive env vars that have secure_keywords in their names
    # typically such env vars point to files containing sensitive data
    patterns = [
        r"com_atlassian_db_config_password_ciphers_algorithm_javax_crypto",
        r"AWS_WEB_IDENTITY_TOKEN_FILE",
    ] + [re.escape(var.strip()) for var in vars_in_allowlist if var.strip()]

    # starts with regex
    combined_pattern = r"^(?:" + "|".join(patterns) + ")"
    exception_prefix_regex = re.compile(combined_pattern, re.IGNORECASE)

    return not exception_prefix_regex.match(key)

def collect_secure_values():
    """
    Collect all sensitive environment variable values.
    Returns:
    - dict: A dictionary of environment variable keys and their values for variables deemed sensitive.
    """
    return {key: value for key, value in os.environ.items() if is_secured_var(key)}

def redact_secured_args(args, secured_values):
    """
    Redact sensitive environment variables in the command arguments.
    Parameters:
    - args (list): A list of command arguments.
    - secured_values (dict): A dictionary of sensitive environment variable values to redact.
    Returns:
    - list: A list of command arguments with sensitive values redacted.
    """
    redacted_args = []
    for arg in args:
        for key, value in secured_values.items():
            if value in arg:
                arg = arg.replace(value, f'#{key}_redacted#')
        redacted_args.append(arg)
    return redacted_args

######################################################################
# Application startup utilities

def check_permissions(home_dir):
    """
    Check and set the permissions of the home directory to ensure they are minimal (0o700) for security reasons.
    Parameters:
    - home_dir (str): The path to the home directory whose permissions will be checked and possibly updated.
    """
    if is_verbose_logging():
        logging.debug("Checking permissions for home directory: %s", home_dir)
    if str2bool(env.get('set_permissions') or True) and check_perms(home_dir, env['run_uid'], env['run_gid'], 0o700) is False:
        if is_verbose_logging():
            logging.debug("Permissions for %s are not set as expected. Updating permissions", home_dir)
        set_tree_perms(home_dir, env['run_user'], env['run_group'], 0o700)
        logging.info("User is currently root. Will change directory ownership and downgrade run user to %s", env['run_user'])


def drop_root(run_user):
    """
    Drop root privileges by changing the process's UID and GID to those of a non-root user.
    Parameters:
    - run_user (str): The name of the user to switch to. This user must exist in the system's user database.
    """
    logging.info("User is currently root. Will downgrade run user to %s", run_user)
    pwd_entry = pwd.getpwnam(run_user)

    uid = pwd_entry.pw_uid
    gid = pwd_entry.pw_gid
    os.environ['USER'] = run_user
    os.environ['HOME'] = pwd_entry.pw_dir
    os.environ['SHELL'] = pwd_entry.pw_shell
    os.environ['LOGNAME'] = run_user

    if is_verbose_logging():
        logging.debug("Attempting to drop root privileges. Target user: %s, UID: %s, GID: %s", run_user, uid, gid)

    os.setgid(gid)
    os.setuid(uid)

    if is_verbose_logging():
        logging.debug("Successfully dropped root privileges. Now running as %s with UID: %s, GID: %s", run_user, uid, gid)


def write_pidfile():
    """
    Write the current process's PID into a file named 'docker-app.pid' located in the application's home directory.
    """
    app_home = env[f"{env['app_name'].lower()}_home"]
    pidfile = f"{app_home}/docker-app.pid"
    if is_verbose_logging():
        logging.debug("Writing PID file %s", pidfile)
    with open(pidfile, 'wt', encoding='utf-8') as fd:
        pid = os.getpid()
        fd.write(str(pid))
    if is_verbose_logging():
        logging.debug("PID file written: %s with PID %s", pidfile, pid)



#This function runs command, but does not return
def exec_app(start_cmd_v, home_dir, name='app', env_cleanup=False):
    """
    Execute a specified application command, handling privilege dropping and environment cleanup as necessary.
    Parameters:
    - start_cmd_v (list): The command to run the application, as a list where the first element is the command and
      the subsequent elements are its arguments.
    - home_dir (str): The application's home directory, used for permission checks.
    - name (str, optional): A human-readable name for the application, used in logging. Defaults to 'app'.
    - env_cleanup (bool, optional): Whether to clean up potentially sensitive environment variables before execution.
      Defaults to False.
    """
    # Collect sensitive values before they are unset
    secured_values = collect_secure_values()

    # Redact secure information in the arguments using the collected values
    redacted_args = redact_secured_args(start_cmd_v, secured_values)

    if is_verbose_logging():
        logging.debug("Preparing to execute %s application. Command: %s}", name, redacted_args)

    if os.getuid() == 0:
        check_permissions(home_dir)
        drop_root(env['run_user'])

    write_pidfile()

    if env_cleanup:
        unset_secure_vars()

    cmd = start_cmd_v[0]
    logging.info("Running %s with command '%s', arguments %s", name, cmd, redacted_args)
    if is_verbose_logging():
        logging.debug("Environment variables cleanup: %s", 'enabled' if env_cleanup else 'disabled')
    os.execv(cmd, start_cmd_v)
## This function forks the process and waits for it to finish.
def exec_app_wait(start_cmd_v, home_dir, name='app', env_cleanup=False):

    pid = os.fork()
    if pid == 0:  # Child process
        exec_app(start_cmd_v, home_dir, name, env_cleanup)
    else:  # Parent process
        os.waitpid(pid, 0)
        return
   