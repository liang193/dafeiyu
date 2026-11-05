"""Synthetic integration: no provider keys, messages or external requests."""
import json,os,pathlib,subprocess,tempfile
script=pathlib.Path(__file__).with_name('memory-bridge.mjs')
with tempfile.TemporaryDirectory() as temporary:
 env=dict(os.environ,DAFEIYU_SHARED_MEMORY_DIR=temporary)
 def call(**payload):
  result=subprocess.run(['node',str(script)],input=json.dumps(payload),capture_output=True,text=True,env=env,check=True)
  return json.loads(result.stdout)
 def observe(platform,scope,text,subject='PEER'):
  return call(action='observe',platform=platform,scope=scope,source=text,sourceID='synthetic-source',subject=subject,items=[{'text':text,'relation':'偏好','evidence':text}])
 observe('qq','synthetic-A','合成甲喜欢抹茶')
 assert '抹茶' in call(action='context',platform='qq',scope='synthetic-A',query='抹茶')['context']
 assert '抹茶' not in call(action='context',platform='qq',scope='synthetic-B',query='抹茶')['context']
 assert '抹茶' not in call(action='context',platform='bilibili',scope='public',query='抹茶')['context']
 observe('bilibili','public','公开帖子讨论了合成星球的冰川')
 assert '冰川' in call(action='context',platform='xiaohongshu',scope='public',query='冰川')['context']
 assert '冰川' in call(action='context',platform='qq',scope='synthetic-A',query='冰川')['context']
 observe('qq','synthetic-group','成员甲喜欢钢琴','MEMBER_A')
 observe('qq','synthetic-group','成员乙喜欢小提琴','MEMBER_B')
 context=call(action='context',platform='qq',scope='synthetic-group',query='喜欢')['context']
 assert '钢琴' in context and '小提琴' in context
 before=call(action='snapshot')
 call(action='observe',platform='qq',scope='synthetic-A',source='普通问候',items=[{'text':'伪造经历','evidence':'从未出现'}])
 assert '伪造经历' not in call(action='context',platform='qq',scope='synthetic-A',query='伪造')['context']
 candidate=call(action='propose',text='合成角色说话简短自然',evidence='合成测试')
 assert '合成角色说话简短自然' not in call(action='context',platform='qq',scope='synthetic-B',query='角色')['context']
 call(action='review',id=candidate['id'],decision='accept')
 assert '合成角色说话简短自然' in call(action='context',platform='xiaohongshu',scope='public',query='角色')['context']
 snapshot=call(action='snapshot');assert snapshot['persona']['active']
 assert all(path.stat().st_mode & 0o077 == 0 for path in pathlib.Path(temporary).rglob('ledger.jsonl'))
 print('PASS: fresh-process persistence, cross-platform public recall, private session/member isolation, evidence validation, persona approval and private file permissions.')
