"""Quick Entry commands. Native registration is acknowledged before a binding is reported applied."""
import hashlib
import json
import re
import threading
import time
import uuid
from pathlib import Path


def read(path, fallback):
    try: return json.loads(path.read_text())
    except (OSError, ValueError): return fallback


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False))
    tmp.chmod(0o600)
    tmp.replace(path)


class QuickEntry:
    def __init__(self, state, chat):
        self.state, self.chat = Path(state), chat
        self.lock = threading.Lock()

    def binding(self, value=None):
        with self.lock:
            status = self.state / 'quick-entry-status.json'
            if value is None:
                return read(status, {'binding': 'fn', 'registered': False, 'error': 'Native app has not registered the key yet'})
            if not isinstance(value, str) or not re.fullmatch(r'fn|(?:(?:ctrl|alt|cmd|shift)\+)*key:[0-9]{1,3}', value):
                raise ValueError('Use fn or modifiers + a macOS key code, e.g. ctrl+alt+key:49 (Space).')
            if value != 'fn' and int(value.rsplit(':',1)[1]) > 127:
                raise ValueError('Key code must be between 0 and 127')
            request = str(uuid.uuid4())
            write(self.state / 'quick-entry-request.json', {'id': request, 'binding': value})
            until = time.monotonic() + 4
            while time.monotonic() < until:
                result = read(status, {})
                if result.get('request') == request:
                    return result
                time.sleep(.05)
            raise ValueError('Native app did not acknowledge the binding. Read quick_entry_binding before retrying.')

    def conversations(self):
        rows = [read(p, {}).get('thread') for p in (self.state / 'quick-entry-receipts').glob('*.json')]
        return sorted([r for r in rows if r], key=lambda r: r['updatedAt'], reverse=True)[:100]

    def capture(self, body):
        text = body.get('text')
        key = body.get('request')
        action = body.get('action')
        if not isinstance(text,str) or not text.strip() or len(text)>100000:
            raise ValueError('Enter text (up to 100000 characters)')
        if action not in ('inbox','agent') or not isinstance(key,str) or not re.fullmatch(r'[a-zA-Z0-9-]{1,80}',key):
            raise ValueError('Invalid capture request')
        text = text.strip()
        digest = hashlib.sha256(json.dumps([action,text,body.get('settings')],sort_keys=True).encode()).hexdigest()
        with self.lock:
            receipt = self.state / 'quick-entry-receipts' / (key+'.json')
            old = read(receipt,{})
            if old:
                if old['digest'] != digest: raise ValueError('This request was already used for different text')
                return old['result']
            if action == 'inbox':
                title = ' '.join(text.split())
                payload = {'title': title if len(title)<=250 else title[:249]+'…'}
                if len(title)>250: payload['body']=text
                result = {'goal':self.chat.api('POST','/api/goals',payload,idempotency_key='quick-entry-'+key)['id']}
            else:
                session = str(uuid.uuid5(uuid.NAMESPACE_URL, 'verticals-quick-entry-'+key))
                self.chat.send(session,text,{'quickEntry':True},body.get('settings'))
                result = {'session':session}
            entry = {'digest':digest,'result':result}
            if action == 'agent':
                settings = body.get('settings') or {}
                entry['thread'] = {'id':result['session'], 'title':text[:80],
                    'provider':settings.get('provider','claude'), 'selection':settings,
                    'updatedAt':int(time.time()*1000), 'status':'idle'}
            write(receipt,entry)
            return result
