from cliproxy.translation.wire.anthropic import AnthropicAdapter
from cliproxy.translation.claude import ClaudeTranslator

def test_thinking_tool_roundtrip():
    body={'model':'claude-opus-5-5','max_tokens':256,'messages':[
        {'role':'user','content':'Spotify araması aç'},
        {'role':'assistant','content':[{'type':'thinking','thinking':'synthetic fixture','signature':'opaque-test-signature'}, {'type':'redacted_thinking','data':'opaque-test'}, {'type':'tool_use','id':'call_test','name':'uygulamaAc','input':{'hedef':'https://open.spotify.com/search/test'}}]},
        {'role':'user','content':[{'type':'tool_result','tool_use_id':'call_test','content':'Arama ekranı açıldı; oynatma doğrulanmadı.'}]}]}
    c=AnthropicAdapter().parse_request(body)
    assert [m.role for m in c.messages]==['user','assistant','tool']
    assert c.messages[1].tool_calls[0].id=='call_test'
    assert c.messages[2].tool_call_id=='call_test'
    assert 'synthetic fixture' not in str(c.model_dump())
    native=ClaudeTranslator().request_to_native(c)
    assert native['messages'][1]['content'][0]['type']=='tool_use'
    assert native['messages'][2]['content'][0]['tool_use_id']=='call_test'
