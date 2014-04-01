module gamelib.queue;

//Based on http://rosettacode.org/wiki/Queue/Usage#Faster_Version
struct GrowableCircularQueue(T)
{
    private size_t len;
    private size_t head, tail;
    private T[] A = [T.init];
    
    bool empty() const pure nothrow
    {
        return len == 0;
    }
    
    void push(immutable T item) pure nothrow
    {
        if (len >= A.length) { // Double the queue.
            const old = A;
            A = new T[A.length * 2];
            A[0 .. (old.length - head)] = old[head .. $];
            if (head)
                A[(old.length - head) .. old.length] = old[0 .. head];
            head = 0;
            tail = len;
        }
        A[tail] = item;
        tail = (tail + 1) & (A.length - 1);
        len++;
    }
    
    T pop() pure
    {
        import std.traits: hasIndirections;
        import std.exception: enforce;

        enforce(len != 0, "GrowableCircularQueue is empty.");
        auto saved = A[head];
        static if (hasIndirections!T)
            A[head] = T.init; // Help for the GC.
        head = (head + 1) & (A.length - 1);
        len--;
        return saved;
    }

    @property auto range() const pure nothrow
    {
        import std.range;
        return take(cycle(A, head), len);
    }

    @property auto length() const pure nothrow { return len; }
    @property void length(size_t newLen) pure
    {
        if(newLen > len)
        {
            foreach(i;0..(newLen - len))
            {
                push(T.init);
            }
        }
        else if(newLen < len)
        {
            foreach(i;0..(len - newLen))
            {
                pop();
            }
        }
    }
}

unittest
{
    auto q = new GrowableCircularQueue!int();
    q.push(10);
    q.push(20);
    q.push(30);
    assert(q.pop() == 10);
    assert(q.pop() == 20);
    assert(q.pop() == 30);
    assert(q.empty());
    
    uint count = 0;
    foreach (immutable i; 1 .. 1_000) {
        foreach (immutable j; 0 .. i)
            q.push(count++);
        foreach (immutable j; 0 .. i)
            q.pop();
    }
}


