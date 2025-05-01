#!/usr/bin/python3 -B

import logging
import re
import pathlib

from entrypoint_helpers import env, gen_cfg, str2bool_or, exec_app


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
    try:
        p = pathlib.Path(f'{CONFLUENCE_INSTALL_DIR}/conf/web.xml')
        t = p.read_text()
        p.write_text(re.sub(r'(<session-timeout>).*?(</session-timeout>)', rf'\g<1>{session_timeout}\g<2>', t))
    except Exception as e:
        logging.warning(f"Failed to update session timeout in web.xml: {e}")

exec_app([f'{CONFLUENCE_INSTALL_DIR}/bin/start-confluence.sh', '-fg'], CONFLUENCE_HOME,
         name='Confluence', env_cleanup=UNSET_SENSITIVE_VARS)
