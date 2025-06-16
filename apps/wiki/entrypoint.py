#!/usr/bin/python3 -B

import logging
import re
import pathlib

from entrypoint_helpers import env, gen_cfg, str2bool_or, exec_app_wait


RUN_USER = env['run_user']
RUN_GROUP = env['run_group']
CONFLUENCE_INSTALL_DIR = env['confluence_install_dir']
CONFLUENCE_HOME = env['confluence_home']
UPDATE_CFG = str2bool_or(env.get('atl_force_cfg_update'), False)
UNSET_SENSITIVE_VARS = str2bool_or(env.get('atl_unset_sensitive_env_vars'), True)

gen_cfg('server.xml.j2', f'{CONFLUENCE_INSTALL_DIR}/conf/server.xml')
gen_cfg('seraph-config.xml.j2',
        f'{CONFLUENCE_INSTALL_DIR}/confluence/WEB-INF/classes/seraph-config.xml')
gen_cfg('confluence-init.properties.j2',
        f'{CONFLUENCE_INSTALL_DIR}/confluence/WEB-INF/classes/confluence-init.properties')
gen_cfg('confluence.cfg.xml.j2', f'{CONFLUENCE_HOME}/confluence.cfg.xml',
        user=RUN_USER, group=RUN_GROUP, overwrite=UPDATE_CFG)

session_timeout = env.get('atl_confluence_session_timeout')
if session_timeout:
    logging.info(f"Updating session timeout to {session_timeout}")
    paths = [
        pathlib.Path(f'{CONFLUENCE_INSTALL_DIR}/conf/web.xml'),
        pathlib.Path(f'{CONFLUENCE_INSTALL_DIR}/confluence/WEB-INF/web.xml'),
    ]
    for path in paths:
        try:
            text = path.read_text()
            updated = re.sub(r'(<session-timeout>).*?(</session-timeout>)', rf'\g<1>{session_timeout}\g<2>', text)
            path.write_text(updated)
            logging.info(f"Updated session timeout in {path}")
        except Exception as e:
            logging.warning(f"Failed to update session timeout in {path}: {e}")


# Run the startup script for conluence, and wait until confluence has been stopped.
exec_app_wait([f'{CONFLUENCE_INSTALL_DIR}/bin/start-confluence.sh', '-fg'], CONFLUENCE_HOME,
        name='Confluence', env_cleanup=UNSET_SENSITIVE_VARS)



# Once confluence has been stopped, run the script that waits for
# catalina.sh to finish shutting down.
# If this is not done /shutdown-wait.sh will exit with error
try:
        exec_app_wait(['/wait-for-catalina-shutdown.sh'], "/",
                name='Waitforshutdown', env_cleanup=UNSET_SENSITIVE_VARS)
except Exception as e:
        exit(1)

