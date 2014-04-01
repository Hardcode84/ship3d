module gamelib.autodispose;

import std.typetuple:staticIndexOf;
import std.traits:isArray,isAssociativeArray;
enum auto_dispose;
mixin template GenerateAutoDispose()
{
    void dispose()
    {
        foreach_reverse(i,t;this.tupleof)
        {
            static if(staticIndexOf!(auto_dispose,__traits(getAttributes, this.tupleof[i])) != -1)
            {
                static if(isArray!(typeof(t)))
                {
                    foreach(t1;t)
                    {
                        if(t1 !is null)
                        {
                            t1.dispose();
                        }
                    }
                }
                else static if(isAssociativeArray!(typeof(t)))
                {
                    foreach(i,v;t)
                    {
                        static if(__traits(compiles,i.dispose()))
                        {
                            if(i !is null)
                            {
                                i.dispose();
                            }
                        }
                        static if(__traits(compiles,v.dispose()))
                        {
                            if(v !is null)
                            {
                                v.dispose();
                            }
                        }
                    }
                }
                else
                {
                    if(t !is null)
                    {
                        t.dispose();
                    }
                }
            }
        }
    }
}