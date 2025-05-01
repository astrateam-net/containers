#!/usr/bin/python3 -B

import logging
import os
import shutil
import re
import pathlib

from entrypoint_helpers import env, gen_cfg, gen_container_id, str2bool, str2bool_or, exec_app


RUN_USER = env['run_user']
RUN_GROUP = env['run_group']
JIRA_INSTALL_DIR = env['jira_install_dir']
JIRA_HOME = env['jira_home']
UPDATE_CFG = str2bool_or(env.get('atl_force_cfg_update'), False)
UNSET_SENSITIVE_VARS = str2bool_or(env.get('atl_unset_sensitive_env_vars'), True)

gen_container_id()
if os.stat('/etc/container_id').st_size == 0:
    gen_cfg('container_id.j2', '/etc/container_id',
            user=RUN_USER, group=RUN_GROUP, overwrite=True)
gen_cfg('server.xml.j2', f'{JIRA_INSTALL_DIR}/conf/server.xml')
gen_cfg('seraph-config.xml.j2',
        f'{JIRA_INSTALL_DIR}/atlassian-jira/WEB-INF/classes/seraph-config.xml')
gen_cfg('dbconfig.xml.j2', f'{JIRA_HOME}/dbconfig.xml',
        user=RUN_USER, group=RUN_GROUP, overwrite=UPDATE_CFG)
if (env.get('atl_s3avatars_bucket_name') and env.get('atl_s3avatars_region')) or \
   (env.get('atl_s3attachments_bucket_name') and env.get('atl_s3attachments_region')) or \
   (env.get('atl_s3backups_bucket_name') and env.get('atl_s3backups_region')):
    gen_cfg('filestore-config.xml.j2', f'{JIRA_HOME}/filestore-config.xml',
        user=RUN_USER, group=RUN_GROUP, overwrite=True)
if str2bool(env.get('clustered')):
    gen_cfg('cluster.properties.j2', f'{JIRA_HOME}/cluster.properties',
            user=RUN_USER, group=RUN_GROUP, overwrite=True)
if env.get('atl_jira_clear_plugin_cache'):
    for dir_name in [".bundled-plugins", ".osgi-plugins"]:
        dir_path = f"{JIRA_HOME}/plugins/{dir_name}"
        if os.path.isdir(dir_path):
            logging.info(f"Clearing Jira plugin cache at {dir_path}")
            shutil.rmtree(dir_path)


session_timeout = env.get('atl_jira_session_timeout')
if session_timeout:
    logging.info(f"Updating session timeout to {session_timeout}")
    try:
        p = pathlib.Path(f'{JIRA_INSTALL_DIR}/conf/web.xml')
        t = p.read_text()
        p.write_text(re.sub(r'(<session-timeout>).*?(</session-timeout>)', rf'\g<1>{session_timeout}\g<2>', t))
    except Exception as e:
        logging.warning(f"Failed to update session timeout in web.xml: {e}")


exec_app([f'{JIRA_INSTALL_DIR}/bin/start-jira.sh', '-fg'], JIRA_HOME,
         name='Jira', env_cleanup=UNSET_SENSITIVE_VARS)
